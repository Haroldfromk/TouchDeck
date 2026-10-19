import Foundation
import Testing
@testable import TouchDeck

@Test func listsOnlyVisibleFoldersSorted() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "folder-lister-\(UUID().uuidString)")
    let fm = FileManager.default
    for dir in ["b", "a", ".git", "Safari.app", "블로그"] {
        try fm.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
    }
    try Data("x".utf8).write(to: root.appending(path: "note.txt"))
    defer { try? fm.removeItem(at: root) }

    // 숨김 폴더, 앱(.app), 파일은 빼고 Finder처럼 이름순.
    // 한글과 영어 중 뭐가 먼저인지는 맥 언어 설정을 따르니(한국어면 한글 먼저) 그 부분은 보지 않는다
    let names = try #require(FolderLister.children(atPath: root.path))
    #expect(Set(names) == ["a", "b", "블로그"])
    #expect(names.filter { $0.allSatisfy(\.isASCII) } == ["a", "b"])
}

@Test func missingFolderIsNil() {
    #expect(FolderLister.children(atPath: "/nope-\(UUID().uuidString)") == nil)
}
