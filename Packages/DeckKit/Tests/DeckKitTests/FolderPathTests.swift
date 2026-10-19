import Testing
@testable import DeckKit

private let home = "/Users/harold"

@Test func abbreviatesHomeToTilde() {
    #expect(FolderPath.abbreviate("/Users/harold/Documents/Workspace", home: home) == "~/Documents/Workspace")
    #expect(FolderPath.abbreviate("/Users/harold", home: home) == "~")
    #expect(FolderPath.abbreviate("/Users/haroldx/a", home: home) == "/Users/haroldx/a")
}

@Test func joinsChild() {
    #expect(FolderPath.child("~", "Documents") == "~/Documents")
    #expect(FolderPath.child("~/Documents", "Workspace") == "~/Documents/Workspace")
}

@Test func parentStopsAtHome() {
    // 폴더 고르기는 홈 폴더 안에서만 다닌다
    #expect(FolderPath.parent("~/Documents/Workspace") == "~/Documents")
    #expect(FolderPath.parent("~/Documents") == "~")
    #expect(FolderPath.parent("~") == nil)
}

@Test func onlyHomeSubtreeIsAllowed() {
    #expect(FolderPath.isInsideHome("~"))
    #expect(FolderPath.isInsideHome("~/Documents"))
    #expect(!FolderPath.isInsideHome("/etc"))
    #expect(!FolderPath.isInsideHome("~/../other"))
}
