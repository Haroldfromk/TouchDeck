import Foundation

/// 영상 프레임 하나를 바이너리 메시지에 싣는 모양 (봉인하기 전).
/// [종류 1바이트: 1=H.264][플래그 1바이트: 1=키프레임]
/// 키프레임이면 [개수 1바이트] + 개수만큼 [길이 2바이트(big endian) + SPS/PPS]
/// 그 뒤 나머지 전부가 프레임 데이터(AVCC: NAL마다 4바이트 길이 + 내용)
public struct VideoPacket: Equatable, Sendable {
    public static let h264: UInt8 = 1

    public var keyframe: Bool
    /// 키프레임에만. 기기의 디코더가 이걸로 영상 형식을 만든다
    public var parameterSets: [Data]
    public var frame: Data

    public init(keyframe: Bool, parameterSets: [Data], frame: Data) {
        self.keyframe = keyframe
        self.parameterSets = keyframe ? parameterSets : []
        self.frame = frame
    }

    public func encoded() -> Data {
        var out = Data([Self.h264, keyframe ? 1 : 0])
        if keyframe {
            out.append(UInt8(parameterSets.count))
            for set in parameterSets {
                out.append(contentsOf: [UInt8(set.count >> 8), UInt8(set.count & 0xFF)])
                out.append(set)
            }
        }
        out.append(frame)
        return out
    }

    /// 모르는 종류이거나 잘린 데이터면 nil
    public static func decode(_ data: Data) -> VideoPacket? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == h264 else { return nil }
        let keyframe = bytes[1] & 1 == 1
        var i = 2
        var sets: [Data] = []
        if keyframe {
            guard i < bytes.count else { return nil }
            let count = Int(bytes[i])
            i += 1
            for _ in 0..<count {
                guard i + 2 <= bytes.count else { return nil }
                let length = Int(bytes[i]) << 8 | Int(bytes[i + 1])
                i += 2
                guard i + length <= bytes.count else { return nil }
                sets.append(Data(bytes[i..<i + length]))
                i += length
            }
        }
        return VideoPacket(keyframe: keyframe, parameterSets: sets, frame: Data(bytes[i...]))
    }
}

/// 보내는 중인 프레임 수를 세서 밀리면 버린다. 와이파이가 느려질 때 지연이 쌓이지 않고 최신 화면으로 따라잡게.
public struct SendGate: Sendable {
    /// 보는 중에 fps를 바꾸면 한도도 바뀐다. 보내는 중인 수는 그대로 이어 간다
    public var limit: Int
    private var inFlight = 0
    /// 하나라도 버렸으면 키프레임이 올 때까지 다 버린다 (버린 프레임을 참조하는 프레임은 깨져 보인다)
    private var waitingForKeyframe = false
    private var keyframeRequested = false

    public init(limit: Int = 2) {
        self.limit = limit
    }

    /// 밀릴 때 버리는 기준을 시간으로 같게: 30fps는 2장, 60fps는 4장 (둘 다 약 0.07초)
    public static func limit(forFPS fps: Int) -> Int {
        max(1, fps / 15)
    }

    /// 이 프레임을 보내도 되면 true (보낸 것으로 센다)
    public mutating func begin(keyframe: Bool) -> Bool {
        if waitingForKeyframe && !keyframe { return false }
        guard inFlight < limit else {
            if !waitingForKeyframe { keyframeRequested = true }
            waitingForKeyframe = true
            return false
        }
        if keyframe { waitingForKeyframe = false }
        inFlight += 1
        return true
    }

    public mutating func finish() {
        inFlight = max(0, inFlight - 1)
    }

    /// 압축기에 다음 프레임을 키프레임으로 달라고 할 때인지. 한 번 읽으면 지운다
    public mutating func takeKeyframeRequest() -> Bool {
        defer { keyframeRequested = false }
        return keyframeRequested
    }
}
