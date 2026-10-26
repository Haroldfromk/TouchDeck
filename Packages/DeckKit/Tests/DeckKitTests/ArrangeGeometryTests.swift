import CoreGraphics
import Testing
@testable import DeckKit

// 3열: 너비 3*100 + 2*14 = 328, 4줄: 높이 4*100 + 3*14 = 442
@Test func slotFromPointThreeColumns() {
    let size = CGSize(width: 328, height: 442)
    #expect(GridSlot.index(at: CGPoint(x: 50, y: 50), size: size, columns: 3, spacing: 14) == 0)
    #expect(GridSlot.index(at: CGPoint(x: 278, y: 50), size: size, columns: 3, spacing: 14) == 2)
    #expect(GridSlot.index(at: CGPoint(x: 50, y: 170), size: size, columns: 3, spacing: 14) == 3)
    #expect(GridSlot.index(at: CGPoint(x: 278, y: 400), size: size, columns: 3, spacing: 14) == 11)
}

@Test func slotFromPointFourColumns() {
    let size = CGSize(width: 442, height: 328)   // 4열 3줄
    #expect(GridSlot.index(at: CGPoint(x: 400, y: 50), size: size, columns: 4, spacing: 14) == 3)
    #expect(GridSlot.index(at: CGPoint(x: 50, y: 170), size: size, columns: 4, spacing: 14) == 4)
}

@Test func gapIsNoSlot() {
    let size = CGSize(width: 328, height: 442)
    #expect(GridSlot.index(at: CGPoint(x: 107, y: 50), size: size, columns: 3, spacing: 14) == nil)
    #expect(GridSlot.index(at: CGPoint(x: 50, y: 107), size: size, columns: 3, spacing: 14) == nil)
}

@Test func outsideIsNoSlot() {
    let size = CGSize(width: 328, height: 442)
    #expect(GridSlot.index(at: CGPoint(x: -1, y: 50), size: size, columns: 3, spacing: 14) == nil)
    #expect(GridSlot.index(at: CGPoint(x: 50, y: 443), size: size, columns: 3, spacing: 14) == nil)
}

@Test func pagerWaitsHalfSecondThenRepeats() {
    var p = EdgePager()
    #expect(p.update(x: 390, width: 400, page: 0, pageCount: 3, now: 0) == 0)
    #expect(p.update(x: 390, width: 400, page: 0, pageCount: 3, now: 0.49) == 0)
    #expect(p.update(x: 390, width: 400, page: 0, pageCount: 3, now: 0.5) == 1)
    #expect(p.update(x: 390, width: 400, page: 1, pageCount: 3, now: 1.1) == 0)
    #expect(p.update(x: 390, width: 400, page: 1, pageCount: 3, now: 1.21) == 1)
}

@Test func pagerLeftEdgeGoesBack() {
    var p = EdgePager()
    _ = p.update(x: 10, width: 400, page: 2, pageCount: 3, now: 0)
    #expect(p.update(x: 10, width: 400, page: 2, pageCount: 3, now: 0.5) == -1)
}

@Test func pagerStopsAtEnds() {
    var p = EdgePager()
    _ = p.update(x: 10, width: 400, page: 0, pageCount: 3, now: 0)
    #expect(p.update(x: 10, width: 400, page: 0, pageCount: 3, now: 1) == 0)
    _ = p.update(x: 390, width: 400, page: 2, pageCount: 3, now: 2)
    #expect(p.update(x: 390, width: 400, page: 2, pageCount: 3, now: 3) == 0)
}

@Test func leavingEdgeResetsTimer() {
    var p = EdgePager()
    _ = p.update(x: 390, width: 400, page: 0, pageCount: 3, now: 0)
    _ = p.update(x: 200, width: 400, page: 0, pageCount: 3, now: 0.3)
    _ = p.update(x: 390, width: 400, page: 0, pageCount: 3, now: 0.4)
    #expect(p.update(x: 390, width: 400, page: 0, pageCount: 3, now: 0.8) == 0)
    #expect(p.update(x: 390, width: 400, page: 0, pageCount: 3, now: 0.91) == 1)
}
