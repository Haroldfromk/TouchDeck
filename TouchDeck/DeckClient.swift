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
    private(set) var folderListing: FolderListing?
    /// 지금 맥과 붙어 있는 길 (같은 와이파이 / 직접 연결 등)
    private(set) var route: ConnectionRoute?

    /// 맥 화면 보기: 지금 받고 있는 영상
    struct ScreenStream: Equatable {
        let displayId: UInt32
        let width: Int
        let height: Int
    }

    /// 맥이 화면 보기 요청에 답한 것 (허용 안 됨, 권한 없음 등). 같은 답이 다시 와도 새로 보이게 id를 둔다
    struct ScreenNotice: Equatable {
        let id = UUID()
        let state: ScreenState
        let message: String?
    }

    private(set) var displays: [DisplayInfo] = []
    private(set) var displayThumbnails: [UInt32: UIImage] = [:]
    private(set) var screenStream: ScreenStream?
    private(set) var screenNotice: ScreenNotice?
    @ObservationIgnored let video = VideoRenderer()
    @ObservationIgnored private var lastKeyframeRequest = Date.distantPast

    struct FolderListing: Equatable {
        let path: String
        let children: [String]
        let ok: Bool
    }

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
        let browser = NWBrowser(for: .bonjour(type: DeckConstants.serviceType, domain: nil), using: DeckNetwork.browseParameters())
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

    /// 숫자 키패드. 맥에서 앞에 떠 있는 앱에 이 키를 누른 것처럼 입력된다. 친 키는 기억하지 않는다.
    func typeKey(_ key: TypedKey) { send(.typeKey(key)) }

    /// 폴더 고르기: 맥에 이 폴더의 하위 폴더 목록을 묻는다. 답은 folderListing으로 온다
    func listFolder(_ path: String) { send(.listFolder(path: path)) }

    // MARK: - 맥 화면

    // 화면 요청은 허락받은 뒤 봉투 안에서만. 허락 전에 평문으로 나가면 맥이 인사부터 다시 하게 된다
    func listDisplays() {
        guard isConnected else { return }
        screenNotice = nil
        send(.listDisplays)
    }

    /// 이 기기 화면의 실제 픽셀 크기로 받는다. 그보다 작게 받으면 늘려서 보여주느라 글자가 흐려진다
    func startScreen(_ displayId: UInt32) {
        guard isConnected else { return }
        screenNotice = nil
        video.reset()
        send(.startScreen(displayId: displayId, maxSide: screenPixelLongSide, fps: 30, audio: false))
    }

    /// 11인치 아이패드는 2388, 12.9인치는 2732
    private var screenPixelLongSide: Int {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
        let size = screen?.nativeBounds.size ?? CGSize(width: 1920, height: 1080)
        return Int(max(size.width, size.height))
    }

    func stopScreen() {
        if isConnected { send(.stopScreen) }
        screenStream = nil
        video.reset()
    }

    func pointer(_ event: PointerEvent) {
        guard screenStream != nil else { return }
        send(.pointer(event))
    }

    /// 영상이 깨졌거나 처음이다. 맥이 키프레임을 하나 보내 주면 다시 또렷해진다 (0.5초에 한 번까지)
    func requestKeyframe() {
        guard screenStream != nil, Date.now.timeIntervalSince(lastKeyframeRequest) > 0.5 else { return }
        lastKeyframeRequest = .now
        send(.requestKeyframe)
    }

    /// 영상 프레임은 허락받은 접속에서, 이번 접속 키로 봉인된 것만 그린다
    private func receiveBinary(_ data: Data) {
        guard var secure, screenStream != nil else { return }
        do {
            let plain = try secure.openBinary(data)
            self.secure = secure
            guard let packet = VideoPacket.decode(plain) else { return }
            if !video.enqueue(packet) { requestKeyframe() }
        } catch {
            print("[client] bad frame:", error)
        }
    }

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
        channel.onBinary = { [weak self] data in
            MainActor.assumeIsolated { self?.receiveBinary(data) }
        }
        channel.onState = { [weak self, weak channel] state in
            MainActor.assumeIsolated {
                guard let self, let channel, channel === self.channel else { return }
                self.connectionChanged(state)
            }
        }
        // 같은 와이파이에서 직접 연결로 바뀌는 것처럼 길이 바뀌면 표시도 바꾼다
        channel.connection.pathUpdateHandler = { [weak self, weak channel] path in
            MainActor.assumeIsolated {
                guard let self, let channel, channel === self.channel else { return }
                self.route = ConnectionRoute(path: path)
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
        route = nil
        secure = nil
        pendingPairing = nil
        screenStream = nil
        displays = []
        video.reset()
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
        case .folder(let path, let children, let ok):
            folderListing = FolderListing(path: path, children: children, ok: ok)
        case .pressResult(let page, let index, let ok, let message):
            lastResult = PressFeedback(page: page, index: index, ok: ok, message: message)
        case .displays(let items):
            displays = items
            displayThumbnails = Dictionary(uniqueKeysWithValues: items.compactMap { item in
                Data(base64Encoded: item.thumbnail).flatMap(UIImage.init(data:)).map { (item.id, $0) }
            })
        case .screenStarted(let displayId, let width, let height):
            screenStream = ScreenStream(displayId: displayId, width: width, height: height)
            lastKeyframeRequest = .distantPast
            requestKeyframe()
        case .screenStatus(let state, let message):
            screenNotice = ScreenNotice(state: state, message: message)
            // 조작만 안 되는 거면 화면은 계속 본다
            if state != .ok && state != .noInput {
                screenStream = nil
                video.reset()
            }
        case .volume(let value, let muted, let available, let keysAllowed):
            if Date.now.timeIntervalSince(lastLocalVolumeChange) > 2 { volume = value }
            self.muted = muted
            volumeAvailable = available
            volumeKeysAllowed = keysAllowed
        }
    }
}
