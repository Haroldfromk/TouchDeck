import Foundation
import Network
import Testing
@testable import DeckKit

@Test(.timeLimit(.minutes(1)))
func echoesTextOverLoopback() async throws {
    let queue = DispatchQueue(label: "test")
    let listener = try NWListener(using: DeckNetwork.parameters(), on: .any)
    let serverChannels = ChannelBox()
    listener.newConnectionHandler = { connection in
        let channel = WebSocketChannel(connection: connection)
        channel.onText = { [weak channel] text in channel?.send(text) }
        serverChannels.keep(channel)
        channel.start(queue: queue)
    }

    let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { cont in
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: cont.resume(returning: listener.port!)
            case .failed(let error): cont.resume(throwing: error)
            default: break
            }
        }
        listener.start(queue: queue)
    }

    // WebSocket 클라이언트는 host:port 로 붙으면 POSIX 53(connection abort)으로 실패한다.
    // HTTP 업그레이드 요청을 만들 주소가 필요해서 ws:// URL 이나 Bonjour 서비스로 붙어야 한다.
    let url = URL(string: "ws://127.0.0.1:\(port.rawValue)/")!
    let client = WebSocketChannel(connection: NWConnection(to: .url(url), using: DeckNetwork.parameters()))
    let (stream, continuation) = AsyncStream.makeStream(of: String.self)
    client.onText = { continuation.yield($0) }
    client.onState = { state in
        if case .ready = state { client.send(#"{"type":"getApps"}"#) }
    }
    client.start(queue: queue)

    var iterator = stream.makeAsyncIterator()
    let echoed = await iterator.next()
    #expect(echoed == #"{"type":"getApps"}"#)

    client.cancel()
    listener.cancel()
}

final class ChannelBox: @unchecked Sendable {
    private var channels: [WebSocketChannel] = []
    private let lock = NSLock()
    func keep(_ c: WebSocketChannel) { lock.withLock { channels.append(c) } }
}

/// 맥 앱이 꺼지면(서버 쪽 연결이 사라지면) 클라이언트가 알아차려야 다시 찾으러 간다.
@Test(.timeLimit(.minutes(2)))
func clientNoticesWhenServerGoesAway() async throws {
    let queue = DispatchQueue(label: "test-close")
    let listener = try NWListener(using: DeckNetwork.parameters(), on: .any)
    let server = ChannelBox()
    listener.newConnectionHandler = { connection in
        let channel = WebSocketChannel(connection: connection)
        server.keep(channel)
        channel.onState = { state in
            // 서버가 붙자마자 연결을 끊는다 (맥 앱 종료 흉내)
            if case .ready = state { channel.cancel() }
        }
        channel.start(queue: queue)
    }
    let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { cont in
        listener.stateUpdateHandler = { state in
            if case .ready = state { cont.resume(returning: listener.port!) }
        }
        listener.start(queue: queue)
    }

    let url = URL(string: "ws://127.0.0.1:\(port.rawValue)/")!
    let client = WebSocketChannel(connection: NWConnection(to: .url(url), using: DeckNetwork.parameters()))
    let (stream, continuation) = AsyncStream.makeStream(of: String.self)
    client.onState = { state in
        switch state {
        case .failed, .cancelled: continuation.yield("closed")
        default: break
        }
    }
    client.start(queue: queue)

    let start = ContinuousClock.now
    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == "closed")
    #expect(ContinuousClock.now - start < .seconds(5), "끊긴 걸 5초 안에 알아차려야 한다")
    listener.cancel()
}
