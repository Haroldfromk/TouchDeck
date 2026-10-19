import Testing
@testable import TouchDeck

@Test func oldestPendingIsDroppedWhenFull() {
    #expect(PreAuthLimits.toDrop(pending: [1, 2, 3]) == [])
    #expect(PreAuthLimits.toDrop(pending: Array(1...7)) == [])
    #expect(PreAuthLimits.toDrop(pending: Array(1...8)) == [1])
    #expect(PreAuthLimits.toDrop(pending: Array(1...10)) == [1, 2, 3])
}

@Test func preAuthMessageSizeIsLimited() {
    #expect(PreAuthLimits.allows(String(repeating: "a", count: 8 * 1024)))
    #expect(!PreAuthLimits.allows(String(repeating: "a", count: 8 * 1024 + 1)))
    // 글자 수가 아니라 바이트 수로 센다 (한글 한 글자는 3바이트)
    #expect(!PreAuthLimits.allows(String(repeating: "가", count: 3000)))
}

@Test func longDeviceNameIsShortened() {
    #expect(PreAuthLimits.displayName("Harold's iPad") == "Harold's iPad")
    #expect(PreAuthLimits.displayName(String(repeating: "가", count: 32)) == String(repeating: "가", count: 32))
    #expect(PreAuthLimits.displayName(String(repeating: "가", count: 100)) == String(repeating: "가", count: 32) + "…")
}
