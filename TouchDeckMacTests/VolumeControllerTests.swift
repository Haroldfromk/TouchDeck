import Testing
@testable import TouchDeck

@Test func parsesVolumeSettings() {
    let v = VolumeController.parse("output volume:50, input volume:75, alert volume:100, output muted:false\n")
    #expect(v.value == 50)
    #expect(v.muted == false)
}

@Test func parsesMuted() {
    #expect(VolumeController.parse("output volume:0, input volume:75, alert volume:100, output muted:true").muted)
}

@Test func missingOutputVolumeIsUnavailable() {
    // 모니터(DisplayPort)처럼 소리 크기를 못 바꾸는 장치면 "missing value"가 온다
    let v = VolumeController.parse("output volume:missing value, input volume:36, alert volume:100, output muted:missing value")
    #expect(v.available == false)
    #expect(v.value == 0)
}

@Test func normalOutputIsAvailable() {
    #expect(VolumeController.parse("output volume:50, output muted:false").available)
}
