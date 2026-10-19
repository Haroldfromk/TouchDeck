import Foundation
import Testing
@testable import DeckKit

@Test func audioPacketRoundTrips() {
    let packet = AudioPacket(channels: 2, sampleRate: 48_000, samples: [0, 1, -1, 32767, -32768, 300])
    #expect(AudioPacket.decode(packet.encoded()) == packet)
}

@Test func audioPacketLayout() {
    let bytes = [UInt8](AudioPacket(channels: 2, sampleRate: 48_000, samples: [1, -2]).encoded())
    #expect(bytes == [2, 2, 0x00, 0x00, 0xBB, 0x80, 0x01, 0x00, 0xFE, 0xFF])
}

@Test func audioPacketRejectsBadInput() {
    #expect(AudioPacket.decode(Data([1, 0, 0])) == nil)                    // 영상 종류
    #expect(AudioPacket.decode(Data([2, 2, 0, 0])) == nil)                 // 잘림
    #expect(AudioPacket.decode(Data([2, 0, 0, 0, 0xBB, 0x80])) == nil)     // 채널 0
    #expect(AudioPacket.decode(Data([2, 2, 0, 0, 0xBB, 0x80, 1])) == nil)  // 샘플 반쪽
}

@Test func videoDecodeIgnoresAudio() {
    let audio = AudioPacket(channels: 1, sampleRate: 48_000, samples: [5]).encoded()
    #expect(VideoPacket.decode(audio) == nil)
}

@Test func interleaveClampsAndAlternates() {
    let out = AudioPacket.interleave([[1.0, -1.0, 2.0], [0.0, 0.5, -3.0]])
    #expect(out == [32767, 0, -32767, 16384, 32767, -32767])
}

@Test func durationInSeconds() {
    let packet = AudioPacket(channels: 2, sampleRate: 48_000, samples: Array(repeating: 0, count: 960))
    #expect(packet.duration == 0.01)
}
