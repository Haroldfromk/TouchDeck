import Foundation
import Network

public enum DeckNetwork {
    /// 맥 서버와 기기가 똑같이 쓰는 연결 설정: TCP 위에 WebSocket.
    public static func parameters() -> NWParameters {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        // 앱 목록에 아이콘이 다 들어가서 메시지가 커질 수 있다.
        ws.maximumMessageSize = 16 * 1024 * 1024
        // 맥이 잠들거나 와이파이가 끊기면 닫기 신호 없이 연결이 죽는다.
        // 5초 조용하면 2초 간격으로 3번 확인해서, 약 11초 안에 끊긴 걸 알아챈다.
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let params = NWParameters(tls: nil, tcp: tcp)
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        // 같은 와이파이가 아니어도 근처에 있으면 붙게 (에어드롭처럼 기기끼리 직접 연결)
        params.includePeerToPeer = true
        return params
    }

    /// 아이패드가 Bonjour로 맥을 찾을 때. 직접 연결로 광고하는 맥도 찾게 한다.
    public static func browseParameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        return params
    }
}

/// NWConnection 하나 위에서 WebSocket 텍스트 메시지를 주고받는다.
/// 콜백은 `start(queue:)` 전에 정하고, 모든 콜백은 그 큐에서 불린다.
public final class WebSocketChannel: @unchecked Sendable {
    public let connection: NWConnection
    public var onText: (@Sendable (String) -> Void)?
    public var onState: (@Sendable (NWConnection.State) -> Void)?

    public init(connection: NWConnection) {
        self.connection = connection
    }

    public func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onState?(state)
        }
        connection.start(queue: queue)
        receiveNext()
    }

    public func send(_ text: String) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [meta])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true,
                        completion: .contentProcessed { [weak self] error in
                            // 보내기가 실패하면 연결이 죽은 것이다. 닫아서 .cancelled를 알린다.
                            if error != nil { self?.connection.cancel() }
                        })
    }

    public func cancel() {
        connection.cancel()
    }

    private func receiveNext() {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if let content, meta?.opcode == .text, let text = String(data: content, encoding: .utf8) {
                self.onText?(text)
            }
            // 상대가 사라지면 받기는 오류로 끝나지만 연결 상태는 ready로 남는다.
            // 직접 닫아서 .cancelled를 알려야 다시 찾으러 갈 수 있다.
            // 닫기 신호 없이 사라지면 오류도 내용도 없이 끝날 수 있다. 그것도 닫힘으로 본다.
            if error != nil || meta?.opcode == .close || (content == nil && meta == nil) {
                self.connection.cancel()
                return
            }
            self.receiveNext()
        }
    }
}
