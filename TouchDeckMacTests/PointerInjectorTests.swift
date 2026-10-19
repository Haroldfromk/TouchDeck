import CoreGraphics
import DeckKit
import Foundation
import Testing
@testable import TouchDeck

private let display = CGRect(x: -1512, y: 0, width: 1512, height: 982)
private let t0 = Date(timeIntervalSince1970: 1000)

@Test func tapIsMoveThenLeftClick() {
    var plan = PointerPlan()
    let steps = plan.steps(for: PointerEvent(kind: .click, x: 0.5, y: 0.5), display: display, now: t0)
    let at = CGPoint(x: -756, y: 491)
    #expect(steps == [.move(at), .leftDown(at, clicks: 1), .leftUp(at, clicks: 1)])
}

@Test func quickSecondTapIsDoubleClick() {
    // 파일을 열려면 맥이 두 번째 클릭을 더블클릭으로 알아봐야 한다
    var plan = PointerPlan()
    _ = plan.steps(for: PointerEvent(kind: .click, x: 0.5, y: 0.5), display: display, now: t0)
    let steps = plan.steps(for: PointerEvent(kind: .click, x: 0.5, y: 0.5), display: display, now: t0.addingTimeInterval(0.3))
    #expect(steps.last == .leftUp(CGPoint(x: -756, y: 491), clicks: 2))
}

@Test func slowOrFarSecondTapIsSingleClick() {
    var plan = PointerPlan()
    _ = plan.steps(for: PointerEvent(kind: .click, x: 0.5, y: 0.5), display: display, now: t0)
    let slow = plan.steps(for: PointerEvent(kind: .click, x: 0.5, y: 0.5), display: display, now: t0.addingTimeInterval(1))
    #expect(slow.last == .leftUp(CGPoint(x: -756, y: 491), clicks: 1))
    let far = plan.steps(for: PointerEvent(kind: .click, x: 0.9, y: 0.5), display: display, now: t0.addingTimeInterval(1.2))
    #expect(far.last.map { if case .leftUp(_, let c) = $0 { c } else { 0 } } == 1)
}

@Test func twoFingerTapIsRightClick() {
    var plan = PointerPlan()
    let steps = plan.steps(for: PointerEvent(kind: .rightClick, x: 0, y: 0), display: display, now: t0)
    let at = CGPoint(x: -1512, y: 0)
    #expect(steps == [.move(at), .rightDown(at), .rightUp(at)])
}

@Test func dragIsDownDraggedUp() {
    var plan = PointerPlan()
    let a = CGPoint(x: -1512, y: 0), b = CGPoint(x: -756, y: 0)
    #expect(plan.steps(for: PointerEvent(kind: .down, x: 0, y: 0), display: display, now: t0) == [.move(a), .leftDown(a, clicks: 1)])
    #expect(plan.steps(for: PointerEvent(kind: .move, x: 0.5, y: 0), display: display, now: t0) == [.leftDragged(b)])
    #expect(plan.steps(for: PointerEvent(kind: .up, x: 0.5, y: 0), display: display, now: t0) == [.leftUp(b, clicks: 1)])
    // 뗀 뒤 움직임은 그냥 이동
    #expect(plan.steps(for: PointerEvent(kind: .move, x: 0, y: 0), display: display, now: t0) == [.move(a)])
}

@Test func upWithoutDownDoesNothing() {
    var plan = PointerPlan()
    #expect(plan.steps(for: PointerEvent(kind: .up, x: 0, y: 0), display: display, now: t0).isEmpty)
}

@Test func scrollMovesPointerThenScrolls() {
    var plan = PointerPlan()
    let steps = plan.steps(for: PointerEvent(kind: .scroll, x: 0.5, y: 0.5, dx: -4, dy: 30), display: display, now: t0)
    #expect(steps == [.move(CGPoint(x: -756, y: 491)), .scroll(dx: -4, dy: 30)])
}

@Test func releasesHeldButtonWhenStopped() {
    // 끌던 중에 화면 보기가 끊기면 맥 마우스 버튼이 눌린 채로 남지 않게
    var plan = PointerPlan()
    _ = plan.steps(for: PointerEvent(kind: .down, x: 0, y: 0), display: display, now: t0)
    #expect(plan.release() == [.leftUp(CGPoint(x: -1512, y: 0), clicks: 1)])
    #expect(plan.release().isEmpty)
}
