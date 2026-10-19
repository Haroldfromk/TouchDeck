import Foundation

/// 맥 소리 한 덩어리를 바이너리 메시지에 싣는 모양 (봉인하기 전). 압축하지 않는다.
/// [종류 1바이트: 2=소리][채널 수 1바이트][샘플레이트 4바이트(big endian)]
/// 그 뒤 나머지 전부가 16비트 샘플(little endian), 채널을 번갈아 (왼, 오, 왼, 오…)
public struct AudioPacket: Equatable, Sendable {
    public static let kind: UInt8 = 2

    public var channels: Int
    public var sampleRate: Int
    public var samples: [Int16]

    public init(channels: Int, sampleRate: Int, samples: [Int16]) {
        self.channels = channels
        self.sampleRate = sampleRate
        self.samples = samples
    }

    /// 이 덩어리가 몇 초 분량인지
    public var duration: Double {
        Double(samples.count) / Double(channels) / Double(sampleRate)
    }

    public func encoded() -> Data {
        let rate = UInt32(sampleRate)
        var out = Data([Self.kind, UInt8(channels),
                        UInt8(rate >> 24), UInt8(rate >> 16 & 0xFF), UInt8(rate >> 8 & 0xFF), UInt8(rate & 0xFF)])
        out.reserveCapacity(6 + samples.count * 2)
        for sample in samples {
            let bits = UInt16(bitPattern: sample)
            out.append(contentsOf: [UInt8(bits & 0xFF), UInt8(bits >> 8)])
        }
        return out
    }

    /// 다른 종류이거나, 잘렸거나, 채널이 0이거나, 샘플이 반쪽이면 nil
    public static func decode(_ data: Data) -> AudioPacket? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6, bytes[0] == kind, bytes[1] > 0, (bytes.count - 6) % 2 == 0 else { return nil }
        let rate = Int(bytes[2]) << 24 | Int(bytes[3]) << 16 | Int(bytes[4]) << 8 | Int(bytes[5])
        guard rate > 0 else { return nil }
        var samples: [Int16] = []
        samples.reserveCapacity((bytes.count - 6) / 2)
        var i = 6
        while i < bytes.count {
            samples.append(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8))
            i += 2
        }
        return AudioPacket(channels: Int(bytes[1]), sampleRate: rate, samples: samples)
    }

    /// 맥이 주는 채널별 실수 배열(-1~1)을 16비트로 바꿔 번갈아 묶는다. 범위를 넘는 값은 끝값으로 자른다
    public static func interleave(_ planar: [[Float]]) -> [Int16] {
        guard let frames = planar.map(\.count).min() else { return [] }
        var out: [Int16] = []
        out.reserveCapacity(frames * planar.count)
        for frame in 0..<frames {
            for channel in planar {
                let value = min(max(channel[frame], -1), 1)
                out.append(Int16((value * 32767).rounded()))
            }
        }
        return out
    }
}
