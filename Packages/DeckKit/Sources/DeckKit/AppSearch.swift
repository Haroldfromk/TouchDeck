import Foundation

/// 앱 고르기 화면의 검색. 한글 이름, 영어 이름(bundle ID 안의 이름), 초성으로 찾는다.
public enum AppSearch {
    private static let initials: [Character] = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
                                                "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

    /// 맞는 앱만 남긴다. 이름 앞에서 맞는 것, 이름 가운데서 맞는 것, 초성으로 맞는 것, bundle ID로 맞는 것 순서.
    /// 같은 순위끼리는 원래 순서(이름순)를 지킨다.
    public static func filter(_ apps: [AppInfo], query: String) -> [AppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return apps }
        return apps.enumerated()
            .compactMap { offset, app in rank(app, q).map { (rank: $0, offset: offset, app: app) } }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .map(\.app)
    }

    /// 이름에서 검색어와 글자 그대로 맞는 부분 (굵게 표시용). 초성이나 bundle ID로 맞았으면 nil.
    public static func matchRange(in name: String, query: String) -> Range<String.Index>? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return name.range(of: q, options: .caseInsensitive)
    }

    private static func rank(_ app: AppInfo, _ q: String) -> Int? {
        let name = app.name.lowercased()
        if name.hasPrefix(q) { return 0 }
        if name.contains(q) { return 1 }
        if q.allSatisfy({ initials.contains($0) }), choseong(app.name).contains(q) { return 2 }
        if app.bundleId.lowercased().contains(q) { return 3 }
        return nil
    }

    /// "미리보기" → "ㅁㄹㅂㄱ". 한글 음절이 아닌 글자는 그대로 둔다.
    static func choseong(_ text: String) -> String {
        String(text.map { ch -> Character in
            guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1,
                  (0xAC00...0xD7A3).contains(scalar.value) else { return ch }
            return initials[Int(scalar.value - 0xAC00) / 588]
        })
    }
}
