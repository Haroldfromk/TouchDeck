import DeckKit
import Foundation
import Network
import Observation

/// 버튼이 실제로 하는 일. 서버는 이게 어떻게 동작하는지 모른다.
@MainActor
protocol DeckActions {
    func run(_ action: ButtonAction) async -> (ok: Bool, message: String?)
    func apps() async -> [AppInfo]
    func volume() async -> (value: Int, muted: Bool, available: Bool, keysAllowed: Bool)
    func setVolume(_ value: Int) async
    /// 볼륨 키 신호를 보낸다. 권한이 없어서 못 보냈으면 false
    func pressVolumeKey(_ key: VolumeKey) async -> Bool
    /// 키패드 키를 앞에 떠 있는 앱에 입력한다. 권한이 없어서 못 보냈으면 false
    func typeKey(_ key: TypedKey) async -> Bool
}

/// NWListener 하나로 WebSocket 서버와 Bonjour 광고를 같이 한다.
/// 모든 네트워크 콜백을 main 큐에서 받아서 상태를 한 곳(MainActor)에서만 바꾼다.
@MainActor
@Observable
final class DeckServer {
    static let port: NWEndpoint.Port = 52801

    private(set) var status = "멈춤"
    private(set) var pairingCode: String?
    private(set) var pairingDeviceName: String?
    private(set) var isPairingLocked = false
    private(set) var connectedDevices: [String] = []
    private(set) var trusted: [TrustedDevice] = []
    /// 맥 메뉴에 보이는 마지막 잠금 풀기
    private(set) var lastUnlock: (device: String, at: Date)?
    let screen = ScreenHost()

    private let store: ConfigStore
    private let actions: DeckActions
    private var config: DeckConfig
    private var authority: PairingAuthority
    private var listener: NWListener?
    private var sessions: [ClientSession] = []
    private var lastVolume: (value: Int, muted: Bool, available: Bool, keysAllowed: Bool)?
    private var volumeWatch: Task<Void, Never>?
    /// 기기별 찍어 보기 막기
    private var unlockLimiters: [String: UnlockLimiter] = [:]
    /// 비밀번호를 치는 중. 겹쳐 오면 두 번 치지 않는다
    private var unlocking = false
    private var lockObservers: [NSObjectProtocol] = []

    init(store: ConfigStore = ConfigStore(), random: (@Sendable () -> UInt32)? = nil, actions: DeckActions) {
        self.store = store
        self.actions = actions
        let config = store.load()
        self.config = config
        self.authority = random.map { PairingAuthority(trusted: config.trustedDevices, random: $0) }
            ?? PairingAuthority(trusted: config.trustedDevices)
        self.trusted = config.trustedDevices
    }

    func start() {
        do {
            let listener = try NWListener(using: DeckNetwork.parameters(), on: Self.port)
            listener.service = NWListener.Service(type: DeckConstants.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
            watchVolume()
            watchLock()
        } catch {
            status = "시작 실패: \(error)"
            print("[server] start failed:", error)
        }
    }

    /// 맥 메뉴의 "새 기기 허락 다시 받기". 가장 최근에 기다리던 기기에게 새 숫자를 준다.
    func unlockPairing() {
        authority.unlock()
        isPairingLocked = false
        if let session = sessions.last(where: { $0.stage == .awaitingPairing }), let deviceId = session.deviceId {
            beginPairing(session, deviceId: deviceId, deviceName: session.deviceName ?? "새 기기")
        }
    }

    /// 맥 메뉴의 기기별 "화면 보기 허용". 끄면 보고 있던 화면도 바로 끊는다.
    func setScreenAllowed(_ allowed: Bool, deviceId: String) {
        authority.setScreenAllowed(allowed, deviceId: deviceId)
        saveTrusted()
        if !allowed { screen.deviceDisallowed(deviceId) }
    }

    /// 맥 메뉴의 기기별 "잠금 풀기 허용". 바꾸면 그 기기의 버튼도 바로 따라간다
    func setUnlockAllowed(_ allowed: Bool, deviceId: String) {
        authority.setUnlockAllowed(allowed, deviceId: deviceId)
        saveTrusted()
        for session in sessions where session.deviceId == deviceId { sendLockState(to: session) }
    }

    func revoke(deviceId: String) {
        screen.deviceDisallowed(deviceId)
        authority.revoke(deviceId: deviceId)
        saveTrusted()
        for session in sessions where session.deviceId == deviceId {
            session.stage = .awaitingHello
            session.secure = nil
            session.send(.unauthorized)
        }
        refreshDevices()
    }

    // MARK: - 연결

    private func listenerChanged(_ state: NWListener.State) {
        print("[server] listener", state)
        switch state {
        case .ready: status = "대기 중 (포트 \(Self.port))"
        case .failed(let error): status = "오류: \(error)"
        case .cancelled: status = "멈춤"
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        let channel = WebSocketChannel(connection: connection)
        let session = ClientSession(channel: channel)
        channel.onText = { [weak self, weak session] text in
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                self.handle(text, from: session)
            }
        }
        // 기기는 맥에 바이너리를 보낼 일이 없다. 오면 끊는다
        channel.onBinary = { [weak session] _ in
            MainActor.assumeIsolated { session?.channel.cancel() }
        }
        channel.onState = { [weak self, weak session] state in
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                switch state {
                case .failed, .cancelled: self.drop(session)
                default: break
                }
            }
        }
        for old in PreAuthLimits.toDrop(pending: sessions.filter { $0.stage != .authorized }) {
            old.channel.cancel()
        }
        sessions.append(session)
        channel.start(queue: .main)
        print("[server] new connection", connection.endpoint)
    }

    private func drop(_ session: ClientSession) {
        sessions.removeAll { $0 === session }
        screen.sessionDropped(session)
        if let deviceId = session.deviceId {
            authority.cancelPairing(deviceId: deviceId)
            pairingCode = authority.currentCode
            if pairingCode == nil { pairingDeviceName = nil }
        }
        refreshDevices()
        print("[server] dropped", session.deviceName ?? "unknown")
    }

    // MARK: - 메시지

    private func handle(_ text: String, from session: ClientSession) {
        // 허락받은 뒤에는 서명된 봉투만 받는다. 서명이 틀리거나 다시 보낸 메시지면 연결을 끊는다.
        if session.stage == .authorized {
            guard var secure = session.secure else { return }
            do {
                let body = try secure.open(text)
                session.secure = secure
                guard let message = try? ClientMessage.decode(body) else { return }
                // 키패드로 친 키(비밀번호일 수 있다)는 로그에 남기지 않는다. 화면 터치는 초당 60번까지 와서 뺀다
                if !Self.isQuiet(message) {
                    print("[server] <- (봉투)", text.prefix(220))
                    print("[server] <- (암호 풀림)", session.deviceName ?? "?", body.prefix(200))
                }
                handleAuthorized(message, from: session)
            } catch {
                print("[server] rejected", error, text.prefix(120))
                session.channel.cancel()
            }
            return
        }

        guard PreAuthLimits.allows(text) else {
            print("[server] too big before authorization:", text.utf8.count)
            session.channel.cancel()
            return
        }
        guard let message = try? ClientMessage.decode(text) else {
            print("[server] bad message:", text.prefix(200))
            return
        }
        // 허락 전에 평문으로 온 잠금 풀기 비밀번호 같은 것도 로그에 남기지 않는다
        if !Self.isQuiet(message) { print("[server] <-", session.deviceName ?? "?", text.prefix(200)) }

        switch (session.stage, message) {
        case (_, .hello(let deviceId, let deviceName, let clientNonce, let protocolVersion)):
            // 이름은 상대가 정한다. 메뉴에 보이는 페어링 대기/연결/허락 목록 모두 이 이름을 쓰니 여기서 자른다
            let deviceName = PreAuthLimits.displayName(deviceName)
            session.deviceId = deviceId
            session.deviceName = deviceName
            session.protocolVersion = protocolVersion
            session.clientNonce = clientNonce
            let macNonce = SessionKeys.makeNonce()
            session.macNonce = macNonce
            if let keys = authority.sessionKeys(deviceId: deviceId, clientNonce: clientNonce, macNonce: macNonce) {
                // 맥이 먼저 "토큰을 안다"는 증명을 보낸다. 토큰을 모르는 가짜 맥은 이걸 못 만든다.
                session.pendingKeys = keys
                session.stage = .awaitingAuth
                session.send(.challenge(nonce: macNonce, proof: keys.macProof))
            } else {
                beginPairing(session, deviceId: deviceId, deviceName: deviceName)
            }

        case (.awaitingAuth, .auth(let proof)):
            guard let deviceId = session.deviceId else { return }
            if let keys = session.pendingKeys, keys.clientProof == proof {
                authorize(session, keys: keys)
            } else {
                // 증명이 틀리면(기기가 토큰을 잃었거나 가짜) 다시 숫자로 허락받게 한다.
                // 기존 허락은 지우지 않는다. 남이 내 기기 ID로 틀린 증명을 보내 허락을 끊는 걸 막기 위해.
                beginPairing(session, deviceId: deviceId, deviceName: session.deviceName ?? "새 기기")
            }

        case (.awaitingPairing, .pair(let publicKey, let proof)):
            guard let deviceId = session.deviceId, let clientNonce = session.clientNonce, let macNonce = session.macNonce else { return }
            switch authority.submit(clientPublicKey: Data(base64Encoded: publicKey) ?? Data(), proof: proof, deviceId: deviceId) {
            case .paired(let token, let macProof):
                pairingCode = nil
                pairingDeviceName = nil
                saveTrusted()
                session.send(.paired(proof: macProof))
                authorize(session, keys: SessionKeys(token: token, clientNonce: clientNonce, macNonce: macNonce))
            case .wrong(let remaining):
                session.send(.pairingFailed(remaining: remaining))
            case .locked:
                lockPairing(session)
            case .notPending:
                // 그 사이 다른 기기가 숫자를 받아 갔다. 이 기기에게 다시 새 숫자를 준다.
                beginPairing(session, deviceId: deviceId, deviceName: session.deviceName ?? "새 기기")
            }

        default:
            session.send(.unauthorized)
        }
    }

    private func beginPairing(_ session: ClientSession, deviceId: String, deviceName: String) {
        session.stage = .awaitingPairing
        session.pendingKeys = nil
        guard let offer = authority.beginPairing(deviceId: deviceId, deviceName: deviceName) else {
            lockPairing(session)
            return
        }
        pairingCode = offer.code
        pairingDeviceName = deviceName
        // 숫자는 메뉴바에만 보인다. 기기에는 맥의 임시 공개 키만 보낸다.
        session.send(.needPairing(publicKey: offer.publicKey.base64EncodedString(), nonce: session.macNonce ?? ""))
    }

    /// 틀린 횟수를 다 썼다. 해롤드가 메뉴에서 풀기 전까지 어떤 기기도 숫자를 받을 수 없다.
    private func lockPairing(_ session: ClientSession) {
        isPairingLocked = true
        pairingCode = nil
        pairingDeviceName = nil
        session.send(.pairingLocked)
    }

    /// 여기서부터 이 접속의 모든 메시지는 서명된 봉투로 오간다.
    private func authorize(_ session: ClientSession, keys: SessionKeys) {
        session.secure = SecureChannel(keys: keys, role: .mac)
        session.pendingKeys = nil
        session.stage = .authorized
        session.send(.authorized(protocolVersion: DeckProtocol.current))
        session.send(.layout(config.layout))
        sendLockState(to: session)
        refreshDevices()
        Task {
            let volume = await actions.volume()
            session.send(.volume(value: volume.value, muted: volume.muted, available: volume.available, keysAllowed: volume.keysAllowed))
            session.send(.apps(await actions.apps()))
        }
    }

    private func handleAuthorized(_ message: ClientMessage, from session: ClientSession) {
        switch message {
        case .press(let page, let index):
            guard config.layout.pages.indices.contains(page),
                  config.layout.pages[page].buttons.indices.contains(index),
                  let button = config.layout.pages[page].buttons[index] else {
                session.send(.pressResult(page: page, index: index, ok: false, message: "빈 칸"))
                return
            }
            Task {
                let result = await actions.run(button.action)
                print("[server] press", button.label, result)
                session.send(.pressResult(page: page, index: index, ok: result.ok, message: result.message))
            }

        case .getApps:
            Task { session.send(.apps(await actions.apps())) }

        case .setButton(let page, let index, let button):
            editLayout(session) { try $0.set(button, page: page, index: index) }

        case .clearButton(let page, let index):
            editLayout(session) { try $0.clear(page: page, index: index) }

        case .setVolume(let value):
            Task {
                await actions.setVolume(value)
                await broadcastVolume()
            }

        case .volumeKey(let key):
            Task {
                _ = await actions.pressVolumeKey(key)
                // 키 신호는 바로 반영되지 않을 수 있어서 잠깐 기다렸다가 읽는다
                try? await Task.sleep(for: .milliseconds(150))
                await broadcastVolume()
            }

        case .typeKey(let key):
            Task { _ = await actions.typeKey(key) }

        case .listFolder(let path):
            // 폴더 고르기는 홈 폴더 안에서만. 문서/데스크탑 폴더를 처음 읽을 땐 macOS가 허락 창을 띄울 수 있다
            guard FolderPath.isInsideHome(path) else {
                session.send(.folder(path: path, children: [], ok: false))
                return
            }
            Task {
                let children = await Task.detached { FolderLister.children(atPath: AlacrittyCommand.expandTilde(path)) }.value
                session.send(.folder(path: path, children: children ?? [], ok: children != nil))
            }

        case .listDisplays:
            screen.listDisplays(for: session, allowed: screenAllowed(session))

        case .startScreen(let displayId, let maxSide, let fps, let audio, let bitrateCap):
            screen.start(session, displayId: displayId, maxSide: maxSide, fps: fps, audio: audio, bitrateCap: bitrateCap, allowed: screenAllowed(session))

        case .stopScreen:
            screen.stop(session)

        case .requestKeyframe:
            screen.requestKeyframe(session)

        case .pointer(let event):
            screen.pointer(event, from: session)

        case .screenOptions(let fps, let audio, let bitrateCap):
            screen.options(session, fps: fps, audio: audio, bitrateCap: bitrateCap)

        case .typeText(let text):
            screen.typeText(text, from: session)

        case .pressKey(let key):
            screen.pressKey(key, from: session)

        case .unlock(let password):
            unlock(password, from: session)

        case .hello, .pair, .auth:
            break
        }
    }

    private func screenAllowed(_ session: ClientSession) -> Bool {
        session.deviceId.map { authority.isScreenAllowed(deviceId: $0) } ?? false
    }

    static func isQuiet(_ message: ClientMessage) -> Bool {
        switch message {
        // 입력칸 글과 특수 키도 비밀번호일 수 있어서 남기지 않는다. 잠금 풀기는 맥 비밀번호 그 자체다
        case .typeKey, .pointer, .requestKeyframe, .typeText, .pressKey, .unlock: true
        default: false
        }
    }

    private func broadcastVolume() async {
        let volume = await actions.volume()
        lastVolume = volume
        broadcast(.volume(value: volume.value, muted: volume.muted, available: volume.available, keysAllowed: volume.keysAllowed))
    }

    /// 키보드나 다른 앱으로 소리를 바꿔도 아이패드 게이지가 따라오게, 붙어 있는 기기가 있을 때만 3초마다 확인한다.
    /// (BetterDisplay에게 묻는 데 1초쯤 걸려서 더 자주 하지 않는다)
    private func watchVolume() {
        volumeWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.sessions.contains(where: { $0.stage == .authorized }) else { continue }
                let volume = await self.actions.volume()
                if let last = self.lastVolume, last == volume { continue }
                self.lastVolume = volume
                self.broadcast(.volume(value: volume.value, muted: volume.muted, available: volume.available, keysAllowed: volume.keysAllowed))
            }
        }
    }

    private func editLayout(_ session: ClientSession, _ edit: (inout DeckLayout) throws -> Void) {
        do {
            try edit(&config.layout)
            try store.save(config)
        } catch {
            print("[server] edit failed:", error)
        }
        broadcast(.layout(config.layout))
    }

    // MARK: - 맥 잠금 풀기

    /// 잠김과 풀림을 macOS 알림으로 받아 기기들에 알린다
    private func watchLock() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            lockObservers.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for session in self.sessions { self.sendLockState(to: session) }
                }
            })
        }
    }

    /// 허락받았고 잠금 풀기를 아는 버전의 기기에만. unlockAllowed는 "허용 켜짐 + 가까운 연결"
    private func sendLockState(to session: ClientSession) {
        guard session.stage == .authorized, session.protocolVersion >= DeckProtocol.unlock else { return }
        let allowed = session.deviceId.map { authority.isUnlockAllowed(deviceId: $0) } ?? false
        session.send(.lockState(locked: ScreenLock.isLocked, unlockAllowed: allowed && isNearby(session)))
    }

    /// 연결 상대 주소가 Tailscale이 아닌지. 주소를 알 수 없으면 가깝지 않은 것으로 본다
    private func isNearby(_ session: ClientSession) -> Bool {
        guard case .hostPort(let host, _) = session.channel.connection.endpoint else { return false }
        return UnlockPolicy.isNearby(host)
    }

    private func unlock(_ password: String, from session: ClientSession) {
        guard let deviceId = session.deviceId else { return }
        let refusal = UnlockPolicy.check(allowed: authority.isUnlockAllowed(deviceId: deviceId),
                                         nearby: isNearby(session),
                                         limiterAllows: unlockLimiters[deviceId, default: UnlockLimiter()].allows(now: .now),
                                         locked: ScreenLock.isLocked)
        if let refusal {
            print("[unlock] refused:", refusal.rawValue)
            return session.send(.unlockResult(refusal))
        }
        guard !unlocking else { return print("[unlock] already typing") }
        unlocking = true
        let name = session.deviceName ?? "기기"
        MacUnlocker.shared.type(password) { [weak self, weak session] typed in
            Task { @MainActor in
                guard let self else { return }
                defer { self.unlocking = false }
                guard typed else {
                    session?.send(.unlockResult(.notLocked))
                    return
                }
                // 잠금 화면이 비밀번호를 확인하고 풀리기까지 기다린다
                try? await Task.sleep(for: .seconds(2))
                if ScreenLock.isLocked {
                    self.unlockLimiters[deviceId, default: UnlockLimiter()].recordFailure(now: .now)
                    session?.send(.unlockResult(.wrongPassword))
                } else {
                    self.unlockLimiters[deviceId, default: UnlockLimiter()].recordSuccess()
                    self.lastUnlock = (name, .now)
                    print("[unlock] unlocked by", name)
                    session?.send(.unlockResult(.unlocked))
                }
            }
        }
    }

    private func broadcast(_ message: ServerMessage) {
        for session in sessions where session.stage == .authorized {
            session.send(message)
        }
    }

    private func saveTrusted() {
        config.trustedDevices = authority.trusted
        trusted = authority.trusted
        do { try store.save(config) } catch { print("[server] save failed:", error) }
    }

    private func refreshDevices() {
        // 기기 앱이 맥보다 예전 버전이면 이름 옆에 알린다
        connectedDevices = sessions.filter { $0.stage == .authorized }.compactMap { session in
            session.deviceName.map { session.protocolVersion < DeckProtocol.current ? "\($0) (앱 업데이트 필요)" : $0 }
        }
    }
}
