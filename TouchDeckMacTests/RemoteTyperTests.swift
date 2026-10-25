import Carbon.HIToolbox
import CoreGraphics
import DeckKit
import Foundation
import Testing
@testable import TouchDeck

@Test func specialKeyStrokes() {
    #expect(RemoteKeys.stroke(for: .shiftTab) == (CGKeyCode(kVK_Tab), .maskShift))
    #expect(RemoteKeys.stroke(for: .controlC) == (CGKeyCode(kVK_ANSI_C), .maskControl))
    #expect(RemoteKeys.stroke(for: .escape) == (CGKeyCode(kVK_Escape), []))
    #expect(RemoteKeys.stroke(for: .enter) == (CGKeyCode(kVK_Return), []))
    #expect(RemoteKeys.stroke(for: .up) == (CGKeyCode(kVK_UpArrow), []))
    // 남아 있는 검색어를 한 번에 고르려고
    #expect(RemoteKeys.stroke(for: .selectAll) == (CGKeyCode(kVK_ANSI_A), .maskCommand))
}

@Test func typesInArrivalOrder() {
    let log = StepLog()
    let typer = RemoteTyper(post: { log.append($0) }, pause: { usleep(1_000) })
    typer.type(String(repeating: "가", count: 45))   // 20, 20, 5
    typer.press(.enter)
    typer.waitUntilIdle()
    #expect(log.steps.count == 4)
    #expect(log.steps.first == .text(String(repeating: "가", count: 20)))
    #expect(log.steps.last == .key(CGKeyCode(kVK_Return), []))
}

/// 여러 스레드에서 쌓아도 되는 기록
final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RemoteStep] = []

    func append(_ step: RemoteStep) {
        lock.lock(); defer { lock.unlock() }
        items.append(step)
    }

    var steps: [RemoteStep] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}
