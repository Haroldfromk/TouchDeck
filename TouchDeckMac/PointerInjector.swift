import CoreGraphics
import DeckKit
import Foundation

/// 아이패드 터치를 맥 마우스 동작 순서로. 이벤트를 만들지 않고 순서만 정해서 테스트할 수 있다.
struct PointerPlan {
    enum Step: Equatable {
        case move(CGPoint)
        /// clicks: 맥이 더블클릭을 알아보는 값(1, 2, 3)
        case leftDown(CGPoint, clicks: Int)
        case leftDragged(CGPoint)
        case leftUp(CGPoint, clicks: Int)
        case rightDown(CGPoint)
        case rightUp(CGPoint)
        case scroll(dx: Double, dy: Double)
    }

    static let doubleClickInterval: TimeInterval = 0.5
    static let doubleClickDistance: CGFloat = 8

    /// 끄는 중이면 왼쪽 버튼이 눌린 자리
    private var held: CGPoint?
    private var lastClick: (at: CGPoint, time: Date, count: Int)?

    mutating func steps(for event: PointerEvent, display: CGRect, now: Date) -> [Step] {
        let p = ScreenGeometry.global(normalized: CGPoint(x: event.x, y: event.y), display: display)
        switch event.kind {
        case .click:
            let count = clickCount(at: p, now: now)
            lastClick = (p, now, count)
            return [.move(p), .leftDown(p, clicks: count), .leftUp(p, clicks: count)]
        case .rightClick:
            return [.move(p), .rightDown(p), .rightUp(p)]
        case .down:
            held = p
            return [.move(p), .leftDown(p, clicks: 1)]
        case .move:
            guard held != nil else { return [.move(p)] }
            held = p
            return [.leftDragged(p)]
        case .up:
            guard held != nil else { return [] }
            held = nil
            return [.leftUp(p, clicks: 1)]
        case .scroll:
            return [.move(p), .scroll(dx: event.dx, dy: event.dy)]
        }
    }

    /// 화면 보기가 끊길 때 눌린 버튼을 뗀다 (맥 마우스가 눌린 채로 남지 않게)
    mutating func release() -> [Step] {
        guard let held else { return [] }
        self.held = nil
        return [.leftUp(held, clicks: 1)]
    }

    private func clickCount(at p: CGPoint, now: Date) -> Int {
        guard let last = lastClick, now.timeIntervalSince(last.time) <= Self.doubleClickInterval,
              hypot(p.x - last.at.x, p.y - last.at.y) <= Self.doubleClickDistance else { return 1 }
        return min(last.count + 1, 3)
    }
}

/// 정해진 순서대로 실제 마우스 이벤트를 보낸다. 키패드와 같은 손쉬운 사용 권한을 쓴다.
enum PointerInjector {
    static func post(_ steps: [PointerPlan.Step]) {
        let source = CGEventSource(stateID: .hidSystemState)
        for step in steps {
            let event: CGEvent?
            switch step {
            case .move(let p):
                event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
            case .leftDown(let p, let clicks):
                event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
            case .leftDragged(let p):
                event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
            case .leftUp(let p, let clicks):
                event = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
            case .rightDown(let p):
                event = CGEvent(mouseEventSource: source, mouseType: .rightMouseDown, mouseCursorPosition: p, mouseButton: .right)
            case .rightUp(let p):
                event = CGEvent(mouseEventSource: source, mouseType: .rightMouseUp, mouseCursorPosition: p, mouseButton: .right)
            case .scroll(let dx, let dy):
                event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)
            }
            // 맥에서 Shift 같은 걸 누르고 있어도 클릭만 들어가게
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }
}
