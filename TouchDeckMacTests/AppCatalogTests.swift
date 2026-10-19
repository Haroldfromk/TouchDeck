import Testing
@testable import TouchDeck

/// 이 맥의 실제 설치 앱을 읽는다.
@Test func scanIncludesFinder() {
    #expect(AppCatalog.scan().contains { $0.bundleId == "com.apple.finder" })
}

@Test func scanIncludesSafariWithIcon() {
    let safari = AppCatalog.scan().first { $0.bundleId == "com.apple.Safari" }
    #expect(safari != nil)
    #expect(safari?.icon.isEmpty == false)
}
