import Foundation

/// 소리 값 읽기가 한 번 삐끗했다고 "값 모름"을 보내면, 아이패드 게이지가 끄는 띠로 바뀌었다가 3초 뒤 돌아온다.
/// 같은 출력 장치에서 10초 안에 읽은 값이 있으면 첫 실패는 그 값으로 덮는다. 두 번 연달아 실패하거나
/// 출력 장치가 바뀌었으면 그대로 "값 모름"을 알린다.
struct VolumeStabilizer {
    struct Reading: Equatable {
        var value: Int
        var muted: Bool
        var available: Bool
    }

    static let window: TimeInterval = 10

    private var lastGood: (reading: Reading, output: String?, at: Date)?
    private var failures = 0

    mutating func stabilize(_ reading: Reading, output: String?, now: Date) -> Reading {
        if reading.available {
            lastGood = (reading, output, now)
            failures = 0
            return reading
        }
        failures += 1
        if failures == 1, let lastGood, lastGood.output == output, now.timeIntervalSince(lastGood.at) <= Self.window {
            return lastGood.reading
        }
        return reading
    }
}
