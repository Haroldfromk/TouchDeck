import Testing
@testable import DeckKit

private let apps = [
    AppInfo(name: "메모", bundleId: "com.apple.Notes", icon: ""),
    AppInfo(name: "미리보기", bundleId: "com.apple.Preview", icon: ""),
    AppInfo(name: "리마인더", bundleId: "com.apple.reminders", icon: ""),
    AppInfo(name: "Safari", bundleId: "com.apple.Safari", icon: ""),
    AppInfo(name: "음악", bundleId: "com.apple.Music", icon: ""),
]

private func names(_ query: String) -> [String] {
    AppSearch.filter(apps, query: query).map(\.name)
}

@Test func emptyQueryReturnsAll() {
    #expect(names("") == apps.map(\.name))
    #expect(names("   ") == apps.map(\.name))
}

@Test func koreanNameMatches() {
    #expect(names("메") == ["메모"])
}

@Test func initialConsonantsMatch() {
    // 초성만 쳐도 찾아진다: ㅁㅁ → 메모, ㅁㄹ → 미리보기
    #expect(names("ㅁㅁ") == ["메모"])
    #expect(names("ㅁㄹ") == ["미리보기"])
}

@Test func englishNameInBundleIdMatches() {
    // 맥 언어가 한국어라 이름은 "메모"지만 notes로도 찾고 싶다
    #expect(names("notes") == ["메모"])
    #expect(names("SAF") == ["Safari"])
}

@Test func prefixMatchesComeFirst() {
    // "리"는 리마인더(앞에서 맞음)와 미리보기(가운데서 맞음) 둘 다 맞는다. 앞에서 맞는 쪽이 먼저
    #expect(names("리") == ["리마인더", "미리보기"])
}

@Test func matchRangeIsFoundForHighlight() {
    let app = apps[1]
    #expect(AppSearch.matchRange(in: app.name, query: "리보") == app.name.range(of: "리보"))
    #expect(AppSearch.matchRange(in: app.name, query: "ㅁㄹ") == nil)
}
