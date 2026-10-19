import DeckKit
import Foundation
import Network
import Observation

/// 버튼이 실제로 하는 일. 서버는 이게 어떻게 동작하는지 모른다.
@MainActor
protocol DeckActions {
    func run(_ action: ButtonAction) async -> (ok: Bool, message: String?)
    func apps() async -> [AppInfo]
    func volume() async -> (value: Int, muted: Bool, available: Bool)
    func setVolume(_ value: Int) async
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
    private(set) var connectedDevices: [String] = []
    private(set) var trusted: [TrustedDevice] = []

    private let store: ConfigStore
    private let actions: DeckActions
    private var config: DeckConfig
    private var authority: PairingAuthority
    private var listener: NWListener?
    private var sessions: [ClientSession] = []

    init(store: ConfigStore = ConfigStore(), actions: DeckActions) {
        self.store = store
        self.actions = actions
        let config = store.load()
        self.config = config
        self.authority = PairingAuthority(trusted: config.trustedDevices)
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
        } catch {
            status = "시작 실패: \(error)"
            print("[server] start failed:", error)
        }
    }

    func revoke(deviceId: String) {
        authority.revoke(deviceId: deviceId)
        saveTrusted()
        for session in sessions where session.deviceId == deviceId {
            session.stage = .awaitingHello
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
        guard let message = try? ClientMessage.decode(text) else {
            print("[server] bad message:", text.prefix(200))
            return
        }
        print("[server] <-", session.deviceName ?? "?", text.prefix(200))

        switch (session.stage, message) {
        case (_, .hello(let deviceId, let deviceName)):
            session.deviceId = deviceId
            session.deviceName = deviceName
            if authority.isTrusted(deviceId: deviceId) {
                let nonce = ClientSession.makeNonce()
                session.stage = .awaitingAuth(nonce: nonce)
                session.send(.challenge(nonce: nonce))
            } else {
                beginPairing(session, deviceId: deviceId, deviceName: deviceName)
            }

        case (.awaitingAuth(let nonce), .auth(let signature)):
            guard let deviceId = session.deviceId else { return }
            if authority.verify(deviceId: deviceId, nonce: nonce, signature: signature) {
                authorize(session)
            } else {
                // 서명이 틀리면(기기가 토큰을 잃었거나 가짜) 다시 숫자로 허락받게 한다.
                // 기존 허락은 지우지 않는다. 남이 내 기기 ID로 틀린 서명을 보내 허락을 끊는 걸 막기 위해.
                beginPairing(session, deviceId: deviceId, deviceName: session.deviceName ?? "새 기기")
            }

        case (.awaitingPairing, .pair(let code)):
            guard let deviceId = session.deviceId else { return }
            switch authority.submit(code: code, deviceId: deviceId) {
            case .paired(let token):
                pairingCode = nil
                pairingDeviceName = nil
                saveTrusted()
                session.send(.paired(token: token))
                authorize(session)
            case .wrong(let remaining):
                session.send(.pairingFailed(remaining: remaining))
            case .regenerated(let newCode):
                pairingCode = newCode
                session.send(.pairingFailed(remaining: PairingAuthority.maxAttempts))
            }

        case (.authorized, _):
            handleAuthorized(message, from: session)

        default:
            session.send(.unauthorized)
        }
    }

    private func beginPairing(_ session: ClientSession, deviceId: String, deviceName: String) {
        pairingCode = authority.beginPairing(deviceId: deviceId, deviceName: deviceName)
        pairingDeviceName = deviceName
        session.stage = .awaitingPairing
        session.send(.needPairing)
    }

    private func authorize(_ session: ClientSession) {
        session.stage = .authorized
        session.send(.authorized)
        session.send(.layout(config.layout))
        refreshDevices()
        Task {
            let volume = await actions.volume()
            session.send(.volume(value: volume.value, muted: volume.muted, available: volume.available))
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
                let volume = await actions.volume()
                broadcast(.volume(value: volume.value, muted: volume.muted, available: volume.available))
            }

        case .hello, .pair, .auth:
            break
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
