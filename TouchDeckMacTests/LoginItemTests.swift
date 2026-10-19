import ServiceManagement
import Testing
@testable import TouchDeck

@Test func toggleFollowsStatus() {
    var item = LoginItem.fake()
    item.status = { .enabled }
    #expect(item.isOn)
    item.status = { .requiresApproval }
    #expect(item.isOn)
    item.status = { .notRegistered }
    #expect(item.isOn == false)
}

@Test func turningOnRegisters() {
    let calls = Captured()
    var item = LoginItem.fake()
    item.register = { calls.args.append("register") }
    item.unregister = { calls.args.append("unregister") }
    #expect(item.set(true) == nil)
    #expect(item.set(false) == nil)
    #expect(calls.args == ["register", "unregister"])
}

@Test func registerFailureGivesReason() {
    var item = LoginItem.fake()
    item.register = { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "안 됨"]) }
    #expect(item.set(true) == "로그인 항목 등록 실패: 안 됨")
}

@Test func approvalNeededShowsNote() {
    var item = LoginItem.fake()
    item.status = { .requiresApproval }
    #expect(item.note == "시스템 설정 > 일반 > 로그인 항목에서 TouchDeck을 허용해 주세요")
}

/// Xcode에서 띄운 앱(DerivedData)을 등록하면 로그인 때 그 빌드가 뜬다.
@Test func appOutsideApplicationsShowsNote() {
    var item = LoginItem.fake()
    item.bundlePath = "/Users/h/TouchDeck/DerivedData/Build/Products/Debug/TouchDeck.app"
    #expect(item.note == "/Applications에 설치한 TouchDeck에서 켜야 다음 로그인에도 그 앱이 떠요")
    item.bundlePath = "/Applications/TouchDeck.app"
    #expect(item.note == nil)
}
