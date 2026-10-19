import DeckKit
import Foundation
import Network
import Observation
import UIKit

/// 같은 와이파이의 맥을 Bonjour로 찾아 붙고, 허락(페어링)을 받고, 버튼 배치를 받아 온다.
/// 네트워크 콜백은 전부 main 큐에서 받아 화면 상태를 한 곳에서만 바꾼다.
@MainActor
@Observable
final class DeckClient {
    enum Phase: Equatable {
        case searching
        case connecting(String)
        case needsPairing(String)
        case pairingFailed(String, remaining: Int)
        case connected(String)
        case localNetworkDenied
    }

    struct PressFeedback: Equatable {
        let id = UUID()
        let page: Int
        let index: Int
        let ok: Bool
        let message: String?
    }

    private(set) var phase: Phase = .searching
    private(set) var layout: DeckLayout = .empty
    private(set) var apps: [AppInfo] = []
    private(set) var icons: [String: UIImage] = [:]
    private(set) var volume = 0
    private(set) var volumeAvailable = true
    private(set) var lastResult: PressFeedback?

    private var browser: NWBrowser?
    private var channel: WebSocketChannel?
    private var macName = ""
    private var pendingVolume: Int?
    private var volumeTask: Task<Void, Never>?
    private var volumeBeforeMute = 50

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: DeckConstants.serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.browserChanged(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.found(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    // MARK: - 보내기

    func press(page: Int, index: Int) { send(.press(page: page, index: index)) }
    func submitPairing(code: String) { send(.pair(code: code)) }
    func setButton(_ button: DeckButton, page: Int, index: Int) { send(.setButton(page: page, index: index, button: button)) }
    func clearButton(page: Int, index: Int) { send(.clearButton(page: page, index: index)) }

    /// 슬라이더를 끄는 동안 메시지가 쏟아지지 않게 0.1초에 한 번만 보낸다.
    func setVolume(_ value: Int) {
        volume = value
        pendingVolume = value
        guard volumeTask == nil else { return }
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            if let value = pendingVolume { send(.setVolume(value)) }
            pendingVolume = nil
            volumeTask = nil
        }
    }

    func toggleMute() {
        if volume > 0 {
            volumeBeforeMute = volume
            setVolume(0)
        } else {
            setVolume(volumeBeforeMute)
        }
    }

    private func send(_ message: ClientMessage) {
        guard let text = try? message.encoded() else { return }
        channel?.send(text)
    }

    // MARK: - 찾기와 연결

    private func browserChanged(_ state: NWBrowser.State) {
        print("[client] browser", state)
        switch state {
        case .waiting(let error), .failed(let error):
            // 로컬 네트워크 권한을 거부하면 Bonjour가 PolicyDenied(-65570)로 막힌다 (TN3179)
            if case .dns(let code) = error, code == -65570 || code == -65555 {
                phase = .localNetworkDenied
            }
        default:
            break
        }
    }

    private func found(_ results: Set<NWBrowser.Result>) {
        guard channel == nil, let result = results.first else { return }
        if case .service(let name, _, _, _) = result.endpoint { macName = name }
        connect(to: result.endpoint)
    }

    private func connect(to endpoint: NWEndpoint) {
        phase = .connecting(macName)
        // Bonjour 서비스 엔드포인트로 바로 WebSocket을 열 수 있다 (host:port로는 안 열렸다)
        let channel = WebSocketChannel(connection: NWConnection(to: endpoint, using: DeckNetwork.parameters()))
        channel.onText = { [weak self] text in
            MainActor.assumeIsolated { self?.receive(text) }
        }
        channel.onState = { [weak self, weak channel] state in
            MainActor.assumeIsolated {
                guard let self, let channel, channel === self.channel else { return }
                self.connectionChanged(state)
            }
        }
        self.channel = channel
        channel.start(queue: .main)
    }

    private func connectionChanged(_ state: NWConnection.State) {
        print("[client] connection", state)
        switch state {
        case .ready:
            send(.hello(deviceId: KeychainStore.deviceId(), deviceName: UIDevice.current.name))
        case .waiting, .failed, .cancelled:
            reconnectLater()
        default:
            break
        }
    }

    /// 맥 앱이 꺼졌거나 와이파이가 끊기면 2초 뒤 처음부터 다시 찾는다.
    private func reconnectLater() {
        channel?.cancel()
        channel = nil
        if phase != .localNetworkDenied { phase = .searching }
        browser?.cancel()
        browser = nil
        Task {
            try? await Task.sleep(for: .seconds(2))
            start()
        }
    }

    // MARK: - 받기

    private func receive(_ text: String) {
        guard let message = try? ServerMessage.decode(text) else {
            print("[client] bad message:", text.prefix(200))
            return
        }
        switch message {
        case .needPairing:
            KeychainStore.clearToken()
            phase = .needsPairing(macName)
        case .pairingFailed(let remaining):
            phase = .pairingFailed(macName, remaining: remaining)
        case .paired(let token):
            KeychainStore.setToken(token)
        case .challenge(let nonce):
            // 토큰이 없으면(앱을 지웠다 깔았을 때) 빈 서명을 보낸다. 맥이 숫자로 다시 허락받게 한다.
            let token = KeychainStore.token() ?? ""
            send(.auth(signature: token.isEmpty ? "" : pairingSignature(token: token, nonce: nonce)))
        case .authorized:
            phase = .connected(macName)
        case .unauthorized:
            // 허락 전에 보낸 요청이거나, 맥 메뉴에서 허락을 취소했다. 처음부터 다시 인사한다.
            // (허락이 취소됐으면 맥이 needPairing을 보내고, 그때 토큰을 지운다)
            send(.hello(deviceId: KeychainStore.deviceId(), deviceName: UIDevice.current.name))
        case .layout(let layout):
            self.layout = layout
        case .apps(let apps):
            self.apps = apps
            icons = Dictionary(uniqueKeysWithValues: apps.compactMap { app in
                Data(base64Encoded: app.icon).flatMap(UIImage.init(data:)).map { (app.bundleId, $0) }
            })
        case .pressResult(let page, let index, let ok, let message):
            lastResult = PressFeedback(page: page, index: index, ok: ok, message: message)
        case .volume(let value, _, let available):
            if pendingVolume == nil { volume = value }
            volumeAvailable = available
        }
    }
}
