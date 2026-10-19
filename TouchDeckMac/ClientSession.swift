import DeckKit
import Foundation
import Network

/// 기기 하나의 접속. 허락받기 전까지는 어떤 요청도 실행하지 않는다.
@MainActor
final class ClientSession: Identifiable {
    enum Stage: Equatable {
        case awaitingHello
        case awaitingAuth(nonce: String)
        case awaitingPairing
        case authorized
    }

    let id = UUID()
    let channel: WebSocketChannel
    var stage: Stage = .awaitingHello
    var deviceId: String?
    var deviceName: String?

    init(channel: WebSocketChannel) {
        self.channel = channel
    }

    func send(_ message: ServerMessage) {
        guard let text = try? message.encoded() else { return }
        channel.send(text)
    }

    static func makeNonce() -> String {
        var rng = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &rng)) }.joined()
    }
}
