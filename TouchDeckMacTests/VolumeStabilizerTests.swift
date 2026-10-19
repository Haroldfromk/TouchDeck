import Foundation
import Testing
@testable import TouchDeck

private let t0 = Date(timeIntervalSince1970: 1_000)

@Test func singleFailureKeepsLastGoodValue() {
    // 한 번 삐끗했다고 아이패드 게이지가 끄는 띠로 바뀌면 안 된다
    var s = VolumeStabilizer()
    #expect(s.stabilize(.init(value: 40, muted: false, available: true), output: "LG ULTRAWIDE", now: t0).value == 40)
    let r = s.stabilize(.init(value: 0, muted: false, available: false), output: "LG ULTRAWIDE", now: t0 + 3)
    #expect(r.available)
    #expect(r.value == 40)
}

@Test func twoFailuresInARowReportUnavailable() {
    var s = VolumeStabilizer()
    _ = s.stabilize(.init(value: 40, muted: false, available: true), output: "LG ULTRAWIDE", now: t0)
    _ = s.stabilize(.init(value: 0, muted: false, available: false), output: "LG ULTRAWIDE", now: t0 + 3)
    #expect(s.stabilize(.init(value: 0, muted: false, available: false), output: "LG ULTRAWIDE", now: t0 + 6).available == false)
}

@Test func oldGoodValueIsNotReused() {
    // 마지막 성공이 10초보다 오래됐으면 그대로 실패를 알린다
    var s = VolumeStabilizer()
    _ = s.stabilize(.init(value: 40, muted: false, available: true), output: "LG ULTRAWIDE", now: t0)
    #expect(s.stabilize(.init(value: 0, muted: false, available: false), output: "LG ULTRAWIDE", now: t0 + 11).available == false)
}

@Test func changedOutputIsNotHidden() {
    // 출력 장치가 바뀌었으면(모니터 → 다른 장치) 옛 값을 쓰면 안 된다
    var s = VolumeStabilizer()
    _ = s.stabilize(.init(value: 40, muted: false, available: true), output: "LG ULTRAWIDE", now: t0)
    #expect(s.stabilize(.init(value: 0, muted: false, available: false), output: "HDMI TV", now: t0 + 1).available == false)
}

@Test func successResetsFailureCount() {
    var s = VolumeStabilizer()
    _ = s.stabilize(.init(value: 40, muted: false, available: true), output: "LG", now: t0)
    _ = s.stabilize(.init(value: 0, muted: false, available: false), output: "LG", now: t0 + 1)
    _ = s.stabilize(.init(value: 41, muted: false, available: true), output: "LG", now: t0 + 2)
    #expect(s.stabilize(.init(value: 0, muted: false, available: false), output: "LG", now: t0 + 3).value == 41)
}
