import Testing
@testable import DeckKit

@Test func dragUnderOneStepSendsNothing() {
    var drag = VolumeDrag(step: 16)
    #expect(drag.update(distance: 10) == [])
}

@Test func eachStepSendsOneKey() {
    var drag = VolumeDrag(step: 16)
    #expect(drag.update(distance: 17) == [.up])
    #expect(drag.update(distance: 50) == [.up, .up])   // 3칸째까지
    #expect(drag.update(distance: 51) == [])
}

@Test func goingBackSendsDown() {
    // 위로 3칸 갔다가 손을 떼지 않고 아래로 내려오면 그만큼 내림
    var drag = VolumeDrag(step: 16)
    _ = drag.update(distance: 48)
    #expect(drag.update(distance: 16) == [.down, .down])
    #expect(drag.update(distance: -20) == [.down, .down])
}

@Test func releaseStartsFromZeroAgain() {
    var drag = VolumeDrag(step: 16)
    _ = drag.update(distance: 40)
    drag.end()
    #expect(drag.update(distance: 17) == [.up])
}
