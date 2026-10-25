import Carbon.HIToolbox
import DeckKit
import Foundation
import Testing
@testable import TouchDeck

/// 다른 스레드에서 끝나는 일을 Bool 하나로 기다린다
private final class Expectation: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private var value = false

    func fulfill(_ result: Bool) {
        value = result
        semaphore.signal()
    }

    func wait() -> Bool? {
        semaphore.wait(timeout: .now() + 2) == .success ? value : nil
    }
}

/// 잠금 확인이 몇 번째인지 센다
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        defer { count += 1 }
        return count
    }
}

@Test func typesWholePasswordThenEnter() {
    let log = StepLog()
    let unlocker = MacUnlocker(post: { log.append($0) }, isLocked: { true }, pause: {})
    let finished = Expectation()
    let password = String(repeating: "가", count: 25) + #""\👍🏽"#
    unlocker.type(password) { finished.fulfill($0) }
    #expect(finished.wait() == true)
    #expect(log.steps.dropLast().map { if case .text(let t) = $0 { t } else { "" } }.joined() == password)
    #expect(log.steps.last == .key(CGKeyCode(kVK_Return), []))
}

@Test func doesNothingWhenNotLocked() {
    let log = StepLog()
    let unlocker = MacUnlocker(post: { log.append($0) }, isLocked: { false }, pause: {})
    let finished = Expectation()
    unlocker.type("secret") { finished.fulfill($0) }
    #expect(finished.wait() == false)
    #expect(log.steps.isEmpty)
}

@Test func stopsWhenUnlockedMidway() {
    let log = StepLog()
    let checks = Counter()
    // 첫 묶음 전에는 잠김, 두 번째 묶음 전부터 안 잠김
    let unlocker = MacUnlocker(post: { log.append($0) }, isLocked: { checks.next() == 0 }, pause: {})
    let finished = Expectation()
    unlocker.type(String(repeating: "a", count: 30)) { finished.fulfill($0) }
    #expect(finished.wait() == false)
    #expect(log.steps == [.text(String(repeating: "a", count: 20))])
}

@MainActor
@Test func unlockIsQuiet() {
    #expect(DeckServer.isQuiet(.unlock(password: "x")))
}

/// 잠금 풀기는 시스템이 "화면 잠김"이라고 할 때만. 화면 보호기만 돌고 있으면(암호 없이 깨어나는 상태) 치지 않는다.
/// 첫 입력에 화면 보호기가 걷히면 나머지 비밀번호가 앞에 떠 있는 앱에 들어간다
@Test func unlockNeedsSystemScreenLock() {
    #expect(ScreenLock.passwordLocked(session: ["CGSSessionScreenIsLocked": NSNumber(value: true)]))
    #expect(!ScreenLock.passwordLocked(session: ["CGSSessionScreenIsLocked": NSNumber(value: false)]))
    #expect(!ScreenLock.passwordLocked(session: [:]))
    #expect(!ScreenLock.passwordLocked(session: nil))
}

/// 잠김/풀림 알림이 온 순간에는 시스템 값이 아직 바뀌기 전일 수 있다. 알림 이름 자체를 믿는다
@Test func lockNotificationNameTellsTheState() {
    #expect(ScreenLock.locked(afterNotification: "com.apple.screenIsLocked") == true)
    #expect(ScreenLock.locked(afterNotification: "com.apple.screenIsUnlocked") == false)
    #expect(ScreenLock.locked(afterNotification: "com.apple.other") == nil)
}

/// 맥 잠그기는 macOS 화면 잠금 단축키 ⌃⌘Q를 누른 것과 같다
@Test func lockStrokeIsControlCommandQ() {
    #expect(MacLocker.stroke == .key(CGKeyCode(kVK_ANSI_Q), [.maskControl, .maskCommand]))
}
