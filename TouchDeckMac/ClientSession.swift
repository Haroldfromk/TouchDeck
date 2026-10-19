import DeckKit
import Foundation
import Network

/// 기기 하나의 접속. 허락받기 전까지는 어떤 요청도 실행하지 않는다.
@MainActor
final class ClientSession: Identifiable {
    enum Stage: Equatable {
        case awaitingHello
        case awaitingAuth
        case awaitingPairing
        case authorized
    }

    let id = UUID()
    let channel: WebSocketChannel
    var stage: Stage = .awaitingHello
    var deviceId: String?
    var deviceName: String?
    var clientNonce: String?
    var macNonce: String?
    /// challenge를 보낸 뒤 기기의 증명을 기다리는 동안의 키
    var pendingKeys: SessionKeys?
    /// 허락받은 뒤의 서명 봉투. 있으면 모든 메시지를 여기에 넣어 보낸다.
    var secure: SecureChannel?

    init(channel: WebSocketChannel) {
        self.channel = channel
    }

    func send(_ message: ServerMessage) {
        guard let text = try? message.encoded() else { return }
        if var secure {
            channel.send(secure.seal(text))
            self.secure = secure
        } else {
            channel.send(text)
        }
    }
}
