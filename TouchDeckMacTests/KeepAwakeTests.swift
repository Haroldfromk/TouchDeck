import Testing
@testable import TouchDeck

@Test func assertionsFollowToggleAndViewing() {
    #expect(KeepAwake.wanted(enabled: true, viewing: false) == [.system, .display])
    #expect(KeepAwake.wanted(enabled: false, viewing: true) == [.display])
    #expect(KeepAwake.wanted(enabled: false, viewing: false) == [])
}
