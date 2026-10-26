import CoreGraphics
import Foundation

/// 옮기기 모드에서 손가락 아래가 몇 번 칸인지 찾는다. 칸 번호는 왼쪽 위부터 줄 순서
public enum GridSlot {
    /// 칸 사이 간격이나 그리드 밖이면 nil
    public static func index(at point: CGPoint, size: CGSize, columns: Int, spacing: CGFloat) -> Int? {
        let rows = DeckConstants.slotsPerPage / columns
        let cellWidth = (size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }
        guard let column = cell(point.x, length: cellWidth, spacing: spacing, count: columns),
              let row = cell(point.y, length: cellHeight, spacing: spacing, count: rows) else { return nil }
        return row * columns + column
    }

    private static func cell(_ value: CGFloat, length: CGFloat, spacing: CGFloat, count: Int) -> Int? {
        let stride = length + spacing
        let n = Int((value / stride).rounded(.down))
        guard n < count, value - CGFloat(n) * stride <= length else { return nil }
        return n
    }
}

/// 끄는 동안 손가락이 그리드 왼쪽이나 오른쪽 가장자리에 머물면 페이지를 넘긴다.
/// 처음에는 0.5초, 계속 머물면 0.7초마다 한 번 더
public struct EdgePager {
    public static let edge: CGFloat = 40
    public static let firstDelay: TimeInterval = 0.5
    public static let repeatDelay: TimeInterval = 0.7

    private var side = 0
    private var since: TimeInterval = 0
    private var flipped = false

    public init() {}

    /// 넘길 방향(-1 앞, +1 뒤) 또는 0. 손가락이 그대로여도 주기적으로 불러야 시간이 간다
    public mutating func update(x: CGFloat, width: CGFloat, page: Int, pageCount: Int, now: TimeInterval) -> Int {
        let current = x < Self.edge ? -1 : (x > width - Self.edge ? 1 : 0)
        let target = page + current
        guard current != 0, (0..<pageCount).contains(target) else {
            reset()
            return 0
        }
        if current != side {
            side = current
            since = now
            flipped = false
            return 0
        }
        guard now - since >= (flipped ? Self.repeatDelay : Self.firstDelay) else { return 0 }
        since = now
        flipped = true
        return current
    }

    public mutating func reset() {
        side = 0
        flipped = false
    }
}
