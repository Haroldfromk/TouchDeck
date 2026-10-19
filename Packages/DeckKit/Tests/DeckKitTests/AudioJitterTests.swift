import Testing
@testable import DeckKit

@Test func waitsForSixtyMsBeforeStarting() {
    var jitter = AudioJitter()
    #expect(jitter.arrive(0.02) == .queue)
    #expect(jitter.arrive(0.02) == .queue)
    #expect(jitter.arrive(0.02) == .queueAndStart)
    #expect(jitter.arrive(0.02) == .queue)
}

@Test func overTwoHundredMsStartsDropping() {
    var jitter = AudioJitter()
    for _ in 0..<10 { _ = jitter.arrive(0.02) }   // 0.2
    #expect(jitter.arrive(0.02) == .drop)
}

@Test func dropsUntilBelowHundredMs() {
    var jitter = AudioJitter()
    for _ in 0..<10 { _ = jitter.arrive(0.02) }
    _ = jitter.arrive(0.02)                        // 버리기 시작
    for _ in 0..<5 { _ = jitter.finished(0.02) }   // 0.1 남음
    #expect(jitter.arrive(0.02) == .drop)
    _ = jitter.finished(0.02)                      // 0.08
    #expect(jitter.arrive(0.02) == .queue)
}

@Test func emptyQueueWaitsAgain() {
    var jitter = AudioJitter()
    for _ in 0..<3 { _ = jitter.arrive(0.02) }
    #expect(jitter.finished(0.02) == false)
    #expect(jitter.finished(0.02) == false)
    #expect(jitter.finished(0.02) == true)
    #expect(jitter.playing == false)
    #expect(jitter.arrive(0.02) == .queue)
}
