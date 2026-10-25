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
        /// 밖에서 붙었는데 이 기기가 아직 허락받지 않았다. 페어링은 집 와이파이에서만
        case needsHomePairing(String)
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
    @ObservationIgnored let audioPlayer = AudioPlayer()
    /// 맥 앱의 기능 번호(허락받을 때 알려 준다). 그 전이나 끊긴 뒤엔 nil
    private(set) var macProtocol: Int?
    /// 화면 보기 30/60과 소리. 집에서 마지막에 고른 값을 기억한다
    private var savedFPS = UserDefaults.standard.object(forKey: "screen.fps") as? Int ?? ScreenFPS.high
    private var savedAudio = UserDefaults.standard.object(forKey: "screen.audio") as? Bool ?? true
    /// 원격 중에 툴바에서 바꾼 값. 그 연결 동안만 쓰고 기억하지 않는다
    private var remoteOverride: (fps: Int, audio: Bool)?
    /// 툴바가 보여 줄 지금 값 (원격이면 원격 값)
    var screenFPS: Int { screenSettings.fps }
    var screenAudio: Bool { screenSettings.audio }

    /// 밖에서 붙을 맥 주소 (Tailscale). nil이면 집에서만 쓴다
    private(set) var remoteHost = UserDefaults.standard.string(forKey: "remote.host")
    /// 지금 연결이 원격 주소로 붙은 것인지
    private(set) var isRemote = false
    /// 원격 주소로 붙으려다 실패했다. 붙으면 다시 false
    private(set) var remoteFailed = false
    @ObservationIgnored private var searchStarted = Date.now
    @ObservationIgnored private var remoteTimer: Task<Void, Never>?
    /// 로컬 네트워크 권한이 꺼져 Bonjour가 막혔다 (이번 찾기에서)
    @ObservationIgnored private var bonjourDenied = false
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

    private var isHomePairingNeeded: Bool {
        if case .needsHomePairing = phase { return true }
        return false
    }

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    // MARK: - 맥 잠금 풀기

    enum UnlockStatus: Equatable {
        case working
        case failed(String)
    }

    /// 맥이 알려 준 잠김 여부와, 이 기기가 이 연결로 풀 수 있는지(맥 메뉴 허용 + 가까운 연결)
    private(set) var macLocked = false
    private(set) var unlockAllowed = false
    private(set) var unlockStatus: UnlockStatus?
    /// 저장된 맥 비밀번호가 없거나 바꾸려 할 때 비밀번호 시트를 띄운다
    var needsMacPassword = false

    /// 맥 앱이 잠금 풀기를 아는 버전인지 (기능 번호 4부터)
    var canUnlock: Bool { (macProtocol ?? DeckProtocol.legacy) >= DeckProtocol.unlock }

    /// 연결돼 있고 맥이 잠겨 있지 않을 때만 버튼, 키패드, 화면 보기를 쓴다. 잠기면 잠금 풀기 버튼만 남는다
    var isUsable: Bool { isConnected && !(canUnlock && macLocked) }

    /// 결정은 맥이 하고(unlockAllowed), 원격 주소로 붙었으면 여기서 한 번 더 거른다
    var showsUnlock: Bool { isConnected && !isRemote && canUnlock && macLocked && unlockAllowed }

    /// Face ID를 거쳐 키체인에서 꺼낸 맥 비밀번호를 봉투에 넣어 보낸다. 꺼낸 값은 보내자마자 버린다
    func unlockMac() async {
        guard showsUnlock, unlockStatus != .working else { return }
        guard MacPasswordStore.hasPassword else {
            needsMacPassword = true
            return
        }
        unlockStatus = .working
        guard let password = await MacPasswordStore.read(reason: "맥 잠금을 풀려면 확인해 주세요") else {
            unlockStatus = nil
            return
        }
        guard showsUnlock else {
            unlockStatus = nil
            return
        }
        send(.unlock(password: password))
        // 맥이 답하지 않으면 연결이 끊긴 채 남은 것으로 본다(아이폰이 잠들어 있던 동안 끊겼을 수 있다). 다시 붙는다
        Task {
            try? await Task.sleep(for: .seconds(8))
            guard unlockStatus == .working else { return }
            reconnectNow()
            unlockStatus = .failed("맥에서 답이 없어 다시 연결하는 중이에요")
        }
    }

    /// 연결이 살아 있는지 모를 때 끊고 처음부터 다시 찾는다(앱을 껐다 켜는 것과 같다)
    func reconnectNow() {
        print("[client] reconnect requested")
        reconnectLater()
    }

    /// 저장 못 하면 이유를 돌려준다
    func saveMacPassword(_ password: String) -> String? {
        MacPasswordStore.save(password)
    }

    func deleteMacPassword() {
        MacPasswordStore.delete()
        unlockStatus = nil
    }

    private static func unlockMessage(_ result: UnlockResult) -> String? {
        switch result {
        case .unlocked: nil
        case .wrongPassword: "맥 비밀번호가 맞지 않아요. 버튼을 길게 눌러 바꿔 주세요"
        case .notLocked: "맥이 이미 풀려 있어요"
        case .notAllowed: "맥 메뉴에서 이 기기의 \"잠금 풀기 허용\"을 켜 주세요"
        case .notNearby: "같은 와이파이에 있을 때만 풀 수 있어요"
        case .tooManyTries: "여러 번 틀려서 5분 동안 쉬어요"
        }
    }

    func start() {
        guard browser == nil else { return }
        searchStarted = .now
        bonjourDenied = false
        // Bonjour로 3초 안에 못 찾으면 원격 주소로 간다
        remoteTimer?.cancel()
        remoteTimer = Task {
            try? await Task.sleep(for: .seconds(RemotePlan.wait))
            guard !Task.isCancelled else { return }
            tryRemote()
        }
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

    /// 입력한 주소를 다듬어 저장한다. 빈 입력은 지우기. 저장 못 하면 이유를 돌려준다
    func setRemoteHost(_ input: String) -> String? {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remoteHost = nil
            remoteFailed = false
            UserDefaults.standard.removeObject(forKey: "remote.host")
            return nil
        }
        guard let host = RemoteAddress.clean(input), RemoteAddress.url(host: host) != nil else {
            return "주소에 빈칸이 있으면 안 돼요. 맥 이름이나 100으로 시작하는 주소만 넣어 주세요"
        }
        remoteHost = host
        remoteFailed = false
        UserDefaults.standard.set(host, forKey: "remote.host")
        // 이미 찾는 중이면 3초를 다시 기다리지 않고 바로 판단한다
        tryRemote()
        return nil
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

    /// 맥 앱이 글자 입력을 아는 버전인지 (기능 번호 2부터)
    var canTypeRemotely: Bool { (macProtocol ?? DeckProtocol.legacy) >= DeckProtocol.textInput }
    /// 맥 앱이 키패드 기호를 아는 버전인지 (기능 번호 3부터)
    var canTypeSymbols: Bool { (macProtocol ?? DeckProtocol.legacy) >= DeckProtocol.symbolKeys }
    /// 맥 앱이 이 기기 앱보다 예전 버전이다
    var macNeedsUpdate: Bool { macProtocol.map { $0 < DeckProtocol.current } ?? false }

    /// 보기 화면 입력칸의 글. 비어 있으면 thenEnter일 때 엔터만 보낸다
    func typeText(_ text: String, thenEnter: Bool) {
        guard screenStream != nil else { return }
        let cleaned = TextInput.clean(text)
        if !cleaned.isEmpty { send(.typeText(text: cleaned)) }
        if thenEnter { send(.pressKey(.enter)) }
    }

    func pressKey(_ key: RemoteKey) {
        guard screenStream != nil else { return }
        send(.pressKey(key))
    }

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
    /// 원격이면 LTE에서도 버티게 낮춘 값 (ScreenQuality)
    func startScreen(_ displayId: UInt32) {
        guard isConnected else { return }
        screenNotice = nil
        video.reset()
        let settings = screenSettings
        if settings.audio { audioPlayer.start(remote: shownRoute == .vpn) }
        send(.startScreen(displayId: displayId, maxSide: settings.maxSide, fps: settings.fps, audio: settings.audio,
                          bitrateCap: settings.bitrateCap))
    }

    /// 보기 화면 툴바에서 30/60이나 소리를 바꿨다. 보고 있지 않으면 맥이 무시한다.
    /// 원격 중에 바꾼 값은 그 연결 동안만 쓰고, 집에서 고른 값은 그대로 둔다
    func setScreenOptions(fps: Int, audio: Bool) {
        let fps = ScreenFPS.normalize(fps)
        if shownRoute == .vpn {
            remoteOverride = (fps, audio)
        } else {
            savedFPS = fps
            savedAudio = audio
            UserDefaults.standard.set(fps, forKey: "screen.fps")
            UserDefaults.standard.set(audio, forKey: "screen.audio")
        }
        let settings = screenSettings
        if settings.audio { audioPlayer.start(remote: shownRoute == .vpn) } else { audioPlayer.stop() }
        if isConnected { send(.screenOptions(fps: settings.fps, audio: settings.audio, bitrateCap: settings.bitrateCap)) }
    }

    /// 상태 줄과 화질이 쓰는 길. 원격 주소로 붙었으면 장치 이름이 무엇이든 원격으로 친다
    /// (아이폰은 Tailscale 연결의 길에 utun을 알려 주지 않고 pdp_ip0(cellular)만 알려 줘서 "기타 연결"로 보였다)
    var shownRoute: ConnectionRoute? { isRemote ? .vpn : route }

    private var screenSettings: ScreenSettings {
        ScreenQuality.settings(route: shownRoute, deviceLongSide: screenPixelLongSide, savedFPS: savedFPS,
                               savedAudio: savedAudio, remoteOverride: remoteOverride)
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
        audioPlayer.stop()
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
            // 첫 바이트로 나눈다: 1은 영상, 2는 소리
            if let packet = VideoPacket.decode(plain) {
                if !video.enqueue(packet) { requestKeyframe() }
            } else if screenAudio, let packet = AudioPacket.decode(plain) {
                audioPlayer.enqueue(packet)
            }
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
        send(.hello(deviceId: KeychainStore.deviceId(), deviceName: UIDevice.current.name, nonce: clientNonce,
                    protocolVersion: DeckProtocol.current))
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
                bonjourDenied = true
                // 원격으로 붙어 있으면 그 상태를 지운다
                guard channel == nil else { return }
                phase = .localNetworkDenied
                // Tailscale 주소는 로컬 네트워크가 아니라 이 권한과 상관없다
                tryRemote()
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

    /// Bonjour로 못 찾았고 원격 주소가 있으면 그리로 붙는다. 이미 채널이 있으면 아무것도 안 한다
    private func tryRemote() {
        // 허락 안 된 기기면 밖에서 다시 붙어 봐야 같은 답이다. 집에 와서 Bonjour로 찾을 때까지 쉰다
        guard channel == nil, browser != nil, !isHomePairingNeeded else { return }
        let step = RemotePlan.next(bonjourFound: false, waited: Date.now.timeIntervalSince(searchStarted),
                                   remoteHost: remoteHost, localNetworkDenied: bonjourDenied)
        guard case .useRemote(let host) = step, let url = RemoteAddress.url(host: host) else { return }
        macName = host
        connect(to: .url(url), remote: true)
        // 맥이 잠들어 있으면 Tailscale 안에서 답 없이 오래 기다린다. 10초 안에 허락까지 못 가면 실패로 친다
        let attempt = channel
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard let attempt, attempt === channel, !isConnected, !isHomePairingNeeded else { return }
            remoteFailed = true
            reconnectLater()
        }
    }

    private func connect(to endpoint: NWEndpoint, remote: Bool = false) {
        isRemote = remote
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
                print("[client] path", path.availableInterfaces.map { "\($0.name)(\($0.type))" }, self.route.map(\.label) ?? "-")
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
            // 허락까지 못 가고 끝난 원격 연결은 Tailscale 쪽 문제일 가능성이 크다
            if isRemote, !isConnected, state != .cancelled { remoteFailed = true }
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
        audioPlayer.stop()
        macProtocol = nil
        macLocked = false
        unlockAllowed = false
        unlockStatus = nil
        isRemote = false
        remoteOverride = nil
        remoteTimer?.cancel()
        // 권한 안내와 "집에서 먼저 허락" 안내는 다시 찾는 동안에도 남겨 둔다
        switch phase {
        case .localNetworkDenied, .needsHomePairing: break
        default: phase = .searching
        }
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
            if isRemote {
                // 밖에서는 숫자를 보여 주지 않는다. 끊고 다시 찾아, 집에 오면 Bonjour로 허락받게 한다
                phase = .needsHomePairing(macName)
                return reconnectLater()
            }
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
        case .authorized(let protocolVersion):
            macProtocol = protocolVersion
            remoteFailed = false
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
                audioPlayer.stop()
            }
        case .lockState(let locked, let allowed):
            macLocked = locked
            unlockAllowed = allowed
            if !locked { unlockStatus = nil }
        case .unlockResult(let result):
            unlockStatus = Self.unlockMessage(result).map(UnlockStatus.failed)
            // 맥이 풀렸다고(또는 이미 풀려 있다고) 했으면 잠김 표시를 스스로 지운다. 풀림 알림을 놓쳐도 버튼이 남지 않게
            if result == .unlocked || result == .notLocked {
                macLocked = false
                unlockStatus = nil
            }
        case .volume(let value, let muted, let available, let keysAllowed):
            if Date.now.timeIntervalSince(lastLocalVolumeChange) > 2 { volume = value }
            self.muted = muted
            volumeAvailable = available
            volumeKeysAllowed = keysAllowed
        }
    }
}
