import Foundation
import Network
import Testing
@testable import DeckKit

private func channels() -> (ipad: SecureChannel, mac: SecureChannel) {
    let keys = SessionKeys(token: Data(repeating: 2, count: 32), clientNonce: "c", macNonce: "m")
    return (SecureChannel(keys: keys, role: .client), SecureChannel(keys: keys, role: .mac))
}

// MARK: - 바이너리 봉인 (영상 프레임)

@Test func sealedBinaryOpensOnOtherSide() throws {
    var (ipad, mac) = channels()
    let frame = Data((0..<5000).map { UInt8($0 % 251) })
    let sealed = mac.sealBinary(frame)
    #expect(try ipad.openBinary(sealed) == frame)
}

@Test func sealedBinaryHidesFrame() {
    var (_, mac) = channels()
    let frame = Data(repeating: 0xAB, count: 64)
    let sealed = mac.sealBinary(frame)
    #expect(sealed.range(of: Data(repeating: 0xAB, count: 16)) == nil)
}

@Test func tamperedBinaryIsRejected() {
    var (ipad, mac) = channels()
    var sealed = mac.sealBinary(Data([1, 2, 3, 4]))
    sealed[sealed.count - 1] ^= 0x01
    #expect(throws: SecureChannel.OpenError.badSignature) { try ipad.openBinary(sealed) }
}

@Test func binaryWithChangedSeqIsRejected() {
    var (ipad, mac) = channels()
    var sealed = mac.sealBinary(Data([1, 2, 3, 4]))
    sealed[7] = 9 // 번호(앞 8바이트)의 마지막 바이트
    #expect(throws: SecureChannel.OpenError.badSignature) { try ipad.openBinary(sealed) }
}

@Test func replayedBinaryIsRejected() throws {
    var (ipad, mac) = channels()
    let sealed = mac.sealBinary(Data([1, 2, 3]))
    _ = try ipad.openBinary(sealed)
    #expect(throws: SecureChannel.OpenError.replayed) { try ipad.openBinary(sealed) }
}

@Test func tooShortBinaryIsRejected() {
    var (ipad, _) = channels()
    #expect(throws: SecureChannel.OpenError.notSecure) { try ipad.openBinary(Data([0, 0, 0])) }
}

@Test func binaryAndTextCountSeparately() throws {
    // 글자 메시지가 많이 오가도 영상 번호와 엉키지 않는다 (둘 다 1부터)
    var (ipad, mac) = channels()
    for _ in 0..<3 { _ = try ipad.open(mac.seal(#"{"type":"authorized"}"#)) }
    let sealed = mac.sealBinary(Data([7]))
    #expect(sealed.prefix(8) == Data([0, 0, 0, 0, 0, 0, 0, 1]))
    #expect(try ipad.openBinary(sealed) == Data([7]))
    #expect(try ipad.open(mac.seal(#"{"type":"unauthorized"}"#)) == #"{"type":"unauthorized"}"#)
}

@Test func textBoxCannotBeReplayedAsBinary() throws {
    // 글자 봉투의 내용을 떼어 바이너리 번호를 붙여도 열리지 않는다 (확인 값에 종류가 들어간다)
    var (ipad, mac) = channels()
    let text = mac.seal(#"{"type":"authorized"}"#)
    let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    let box = try #require(Data(base64Encoded: obj["box"] as! String))
    let forged = Data([0, 0, 0, 0, 0, 0, 0, 1]) + box
    #expect(throws: SecureChannel.OpenError.badSignature) { try ipad.openBinary(forged) }
}

@Test func binaryBoxCannotBeReplayedAsText() throws {
    var (ipad, mac) = channels()
    let sealed = mac.sealBinary(Data(#"{"type":"authorized"}"#.utf8))
    let forged = #"{"box":"\#(sealed.dropFirst(8).base64EncodedString())","seq":1,"type":"secure"}"#
    #expect(throws: SecureChannel.OpenError.badSignature) { try ipad.open(forged) }
}

@Test func binaryCannotBeBouncedBackToSender() {
    var (_, mac) = channels()
    var mac2 = mac
    let sealed = mac.sealBinary(Data([1]))
    #expect(throws: SecureChannel.OpenError.badSignature) { try mac2.openBinary(sealed) }
}

// MARK: - 영상 묶음

@Test func keyframePacketRoundTrips() throws {
    let packet = VideoPacket(keyframe: true, parameterSets: [Data([0x67, 1, 2, 3]), Data([0x68, 9])],
                             frame: Data([0, 0, 0, 3, 0x65, 0xAA, 0xBB]))
    let data = packet.encoded()
    #expect(data[0] == 1) // H.264
    #expect(data[1] == 1) // 키프레임
    #expect(VideoPacket.decode(data) == packet)
}

@Test func deltaPacketCarriesNoParameterSets() throws {
    let packet = VideoPacket(keyframe: false, parameterSets: [], frame: Data([0, 0, 0, 2, 0x41, 0x01]))
    let data = packet.encoded()
    #expect(data.count == 2 + packet.frame.count)
    #expect(VideoPacket.decode(data) == packet)
}

@Test func truncatedPacketIsNil() {
    let data = VideoPacket(keyframe: true, parameterSets: [Data(repeating: 7, count: 20)], frame: Data([1])).encoded()
    #expect(VideoPacket.decode(data.prefix(10)) == nil)
    #expect(VideoPacket.decode(Data([1])) == nil)
    #expect(VideoPacket.decode(Data()) == nil)
}

@Test func unknownCodecPacketIsNil() {
    var data = VideoPacket(keyframe: false, parameterSets: [], frame: Data([1, 2])).encoded()
    data[0] = 2
    #expect(VideoPacket.decode(data) == nil)
}

// MARK: - 채널

@Test(.timeLimit(.minutes(1)))
func sendsBinaryOverLoopback() async throws {
    let queue = DispatchQueue(label: "test-binary")
    let listener = try NWListener(using: DeckNetwork.parameters(), on: .any)
    let server = ChannelBox()
    let payload = Data((0..<300_000).map { UInt8($0 % 256) })
    listener.newConnectionHandler = { connection in
        let channel = WebSocketChannel(connection: connection)
        server.keep(channel)
        channel.onText = { [weak channel] _ in channel?.sendBinary(payload) }
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
    let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
    client.onBinary = { continuation.yield($0) }
    client.onState = { state in
        if case .ready = state { client.send("go") }
    }
    client.start(queue: queue)

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == payload)
    client.cancel()
    listener.cancel()
}

@Test func sendGateDropsWhenTwoFramesAreStillSending() {
    var gate = SendGate(limit: 2)
    var sent: [Bool] = []
    sent.append(gate.begin(keyframe: true))
    sent.append(gate.begin(keyframe: false))
    sent.append(gate.begin(keyframe: false))
    #expect(sent == [true, true, false])
    gate.finish()
    gate.finish()
    gate.finish() // 남는 finish가 와도 음수가 되지 않는다
    sent = [gate.begin(keyframe: true), gate.begin(keyframe: true), gate.begin(keyframe: true)]
    #expect(sent == [true, true, false])
}

@Test func sendGateWaitsForKeyframeAfterDrop() {
    // 버린 프레임을 참조하는 프레임은 깨져 보인다. 키프레임이 올 때까지 다 버리고, 압축기에 키프레임을 한 번 요청한다
    var gate = SendGate(limit: 1)
    var steps: [Bool] = []
    steps.append(gate.begin(keyframe: true))
    steps.append(gate.begin(keyframe: false))
    steps.append(gate.takeKeyframeRequest())
    steps.append(gate.takeKeyframeRequest())
    gate.finish()
    steps.append(gate.begin(keyframe: false))
    steps.append(gate.begin(keyframe: true))
    gate.finish()
    steps.append(gate.begin(keyframe: false))
    #expect(steps == [true, false, true, false, false, true, true])
}

// MARK: - fps별 보내기 한도

@Test func gateLimitFollowsFps() {
    #expect(SendGate.limit(forFPS: 30) == 2)
    #expect(SendGate.limit(forFPS: 60) == 4)
}

@Test func changingLimitKeepsInFlight() {
    var gate = SendGate(limit: 2)
    let first = [gate.begin(keyframe: true), gate.begin(keyframe: false)]
    gate.limit = 4
    let more = [gate.begin(keyframe: false), gate.begin(keyframe: false), gate.begin(keyframe: false)]
    #expect(first == [true, true])
    #expect(more == [true, true, false])
}
