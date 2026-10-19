import Foundation
import Network

public enum DeckNetwork {
    /// 맥 서버와 기기가 똑같이 쓰는 연결 설정: TCP 위에 WebSocket.
    public static func parameters() -> NWParameters {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        // 앱 목록에 아이콘이 다 들어가서 메시지가 커질 수 있다.
        ws.maximumMessageSize = 16 * 1024 * 1024
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
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
                        completion: .contentProcessed { _ in })
    }

    public func cancel() {
        connection.cancel()
    }

    private func receiveNext() {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self else { return }
            if let content,
               let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               meta.opcode == .text,
               let text = String(data: content, encoding: .utf8) {
                self.onText?(text)
            }
            if error == nil {
                self.receiveNext()
            }
        }
    }
}
