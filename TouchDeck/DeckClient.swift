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
        case pairingLocked(String)
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
    private(set) var muted = false
    /// macOS가 지금 소리 크기를 아는지 (DisplayPort 모니터면 모른다)
    private(set) var volumeAvailable = true
    /// 맥 앱이 볼륨 키 신호를 보낼 수 있는지 (손쉬운 사용 권한)
    private(set) var volumeKeysAllowed = true
    private(set) var lastResult: PressFeedback?

    private var browser: NWBrowser?
    private var channel: WebSocketChannel?
    private var macName = ""

    private var pendingVolume: Int?
    private var volumeTask: Task<Void, Never>?
    private var lastLocalVolumeChange = Date.distantPast

    // 이번 접속의 키 교환/서명 상태. 접속이 바뀌면 전부 새로 시작한다.
    private var clientNonce = ""
    private var macNonce = ""
    private var macPairingKey: Data?
    private var pendingPairing: PairingCrypto.Derived?
    private var secure: SecureChannel?

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
    /// 숫자는 보내지 않는다. 내 임시 키와 맥의 공개 키로 공유 비밀을 계산하고, 숫자를 섞은 증명만 보낸다.
    func submitPairing(code: String) {
        guard let macPairingKey else { return }
        let key = PairingCrypto.newPrivateKey()
        let mine = key.publicKey.rawRepresentation
        guard let derived = try? PairingCrypto.derive(privateKey: key, peerPublicKey: macPairingKey, code: code,
                                                      macPublicKey: macPairingKey, clientPublicKey: mine) else { return }
        pendingPairing = derived
        send(.pair(publicKey: mine.base64EncodedString(), proof: derived.clientProof))
    }
    func setButton(_ button: DeckButton, page: Int, index: Int) { send(.setButton(page: page, index: index, button: button)) }
    func clearButton(page: Int, index: Int) { send(.clearButton(page: page, index: index)) }

    /// 게이지로 값을 정한다. 끄는 동안 메시지가 쏟아지지 않게 0.1초에 한 번만 보내고,
    /// 맥이 읽어 온 옛 값이 끄는 중인 게이지를 되돌리지 않게 마지막으로 만진 뒤 2초는 맥 값을 무시한다.
    func setVolume(_ value: Int) {
        volume = value
        pendingVolume = value
        lastLocalVolumeChange = .now
        guard volumeTask == nil else { return }
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            if let value = pendingVolume { send(.setVolume(value)) }
            pendingVolume = nil
            volumeTask = nil
        }
    }

    /// 키보드 볼륨 키처럼 올림/내림/음소거만 보낸다. 맥이 같은 신호를 내서 macOS나 BetterDisplay가 받는다.
    func pressVolumeKey(_ key: VolumeKey) { send(.volumeKey(key)) }

    /// 허락받은 뒤에는 서명된 봉투에 넣어 보낸다.
    private func send(_ message: ClientMessage) {
        guard let text = try? message.encoded() else { return }
        if var secure {
            channel?.send(secure.seal(text))
            self.secure = secure
        } else {
            channel?.send(text)
        }
    }

    private func sayHello() {
        secure = nil
        pendingPairing = nil
        clientNonce = SessionKeys.makeNonce()
        send(.hello(deviceId: KeychainStore.deviceId(), deviceName: UIDevice.current.name, nonce: clientNonce))
    }

    /// 상대가 증명을 못 했다. 토큰을 모르는 가짜 맥일 수 있으니 끊고 다시 찾는다.
    private func rejectMac(_ reason: String) {
        print("[client] rejected Mac:", reason)
        reconnectLater()
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
            sayHello()
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
        secure = nil
        pendingPairing = nil
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
        // 허락받은 뒤에는 서명이 맞는 봉투만 믿는다
        if var secure, let body = try? secure.open(text) {
            self.secure = secure
            guard let message = try? ServerMessage.decode(body) else { return }
            handle(message)
            return
        }
        guard let message = try? ServerMessage.decode(text) else {
            print("[client] bad message:", text.prefix(200))
            return
        }
        switch message {
        case .needPairing, .pairingFailed, .pairingLocked, .paired, .challenge, .unauthorized:
            handle(message)
        default:
            // 서명 없는 버튼 배치나 결과는 무시한다 (중간에서 끼워 넣은 것일 수 있다)
            print("[client] unsigned message ignored:", text.prefix(80))
        }
    }

    private func handle(_ message: ServerMessage) {
        switch message {
        case .needPairing(let publicKey, let nonce):
            // 토큰은 새 페어링이 성공할 때까지 지우지 않는다. 가짜 맥이 needPairing을 보내 허락을 끊는 걸 막기 위해.
            secure = nil
            macPairingKey = Data(base64Encoded: publicKey)
            macNonce = nonce
            phase = .needsPairing(macName)
        case .pairingFailed(let remaining):
            phase = .pairingFailed(macName, remaining: remaining)
        case .pairingLocked:
            phase = .pairingLocked(macName)
        case .paired(let proof):
            // 맥도 같은 숫자를 아는지 확인한 뒤에야 토큰을 저장한다
            guard let derived = pendingPairing, derived.macProof == proof else { return rejectMac("pairing proof") }
            KeychainStore.setToken(derived.token.base64EncodedString())
            pendingPairing = nil
            secure = SecureChannel(keys: SessionKeys(token: derived.token, clientNonce: clientNonce, macNonce: macNonce), role: .client)
        case .challenge(let nonce, let proof):
            macNonce = nonce
            guard let token = KeychainStore.token().flatMap({ Data(base64Encoded: $0) }) else {
                // 토큰이 없으면(앱을 지웠다 깔았을 때) 빈 증명을 보낸다. 맥이 숫자로 다시 허락받게 한다.
                return send(.auth(proof: ""))
            }
            let keys = SessionKeys(token: token, clientNonce: clientNonce, macNonce: nonce)
            // 맥이 먼저 토큰을 안다는 걸 증명해야 내 증명을 보낸다
            guard keys.macProof == proof else { return rejectMac("challenge proof") }
            send(.auth(proof: keys.clientProof))
            secure = SecureChannel(keys: keys, role: .client)
        case .authorized:
            phase = .connected(macName)
        case .unauthorized:
            // 허락 전에 보낸 요청이거나, 맥 메뉴에서 허락을 취소했다. 처음부터 다시 인사한다.
            sayHello()
        case .layout(let layout):
            self.layout = layout
        case .apps(let apps):
            self.apps = apps
            icons = Dictionary(uniqueKeysWithValues: apps.compactMap { app in
                Data(base64Encoded: app.icon).flatMap(UIImage.init(data:)).map { (app.bundleId, $0) }
            })
        case .pressResult(let page, let index, let ok, let message):
            lastResult = PressFeedback(page: page, index: index, ok: ok, message: message)
        case .volume(let value, let muted, let available, let keysAllowed):
            if Date.now.timeIntervalSince(lastLocalVolumeChange) > 2 { volume = value }
            self.muted = muted
            volumeAvailable = available
            volumeKeysAllowed = keysAllowed
        }
    }
}
