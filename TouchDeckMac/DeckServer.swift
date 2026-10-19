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

    private let store: ConfigStore
    private let actions: DeckActions
    private var config: DeckConfig
    private var authority: PairingAuthority
    private var listener: NWListener?
    private var sessions: [ClientSession] = []
    private var lastVolume: (value: Int, muted: Bool, available: Bool, keysAllowed: Bool)?
    private var volumeWatch: Task<Void, Never>?

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

    func revoke(deviceId: String) {
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
        channel.onState = { [weak self, weak session] state in
            MainActor.assumeIsolated {
                guard let self, let session else { return }
                switch state {
                case .failed, .cancelled: self.drop(session)
                default: break
                }
            }
        }
        sessions.append(session)
        channel.start(queue: .main)
        print("[server] new connection", connection.endpoint)
    }

    private func drop(_ session: ClientSession) {
        sessions.removeAll { $0 === session }
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
                print("[server] <- (봉투)", text.prefix(220))
                print("[server] <- (서명 확인)", session.deviceName ?? "?", body.prefix(200))
                handleAuthorized(message, from: session)
            } catch {
                print("[server] rejected", error, text.prefix(120))
                session.channel.cancel()
            }
            return
        }

        guard let message = try? ClientMessage.decode(text) else {
            print("[server] bad message:", text.prefix(200))
            return
        }
        print("[server] <-", session.deviceName ?? "?", text.prefix(200))

        switch (session.stage, message) {
        case (_, .hello(let deviceId, let deviceName, let clientNonce)):
            session.deviceId = deviceId
            session.deviceName = deviceName
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
        session.send(.authorized)
        session.send(.layout(config.layout))
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

        case .hello, .pair, .auth:
            break
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
        connectedDevices = sessions.filter { $0.stage == .authorized }.compactMap(\.deviceName)
    }
}
