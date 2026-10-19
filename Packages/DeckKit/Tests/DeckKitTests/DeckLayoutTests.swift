import Foundation
import Testing
@testable import DeckKit

@Test func emptyLayoutHasOnePageOfTwelve() {
    #expect(DeckLayout.empty.pages.count == 1)
    #expect(DeckLayout.empty.pages[0].buttons.count == 12)
}

@Test func settingOnLastPageAppendsEmptyPage() throws {
    var l = DeckLayout.empty
    try l.set(DeckButton(label: "Xcode", action: .app(bundleId: "com.apple.dt.Xcode")), page: 0, index: 3)
    #expect(l.pages.count == 2)
    #expect(l.pages[0].buttons[3]?.label == "Xcode")
}

@Test func clearingTrimsTrailingEmptyPages() throws {
    var l = DeckLayout.empty
    try l.set(DeckButton(label: "a", action: .terminal(directory: nil)), page: 0, index: 0)
    try l.set(DeckButton(label: "b", action: .terminal(directory: nil)), page: 1, index: 0)
    try l.clear(page: 1, index: 0)
    #expect(l.pages.count == 2)
}

@Test func outOfRangeThrows() {
    var l = DeckLayout.empty
    #expect(throws: LayoutError.outOfRange) {
        try l.set(DeckButton(label: "x", action: .terminal(directory: nil)), page: 0, index: 12)
    }
    #expect(throws: LayoutError.outOfRange) { try l.clear(page: 5, index: 0) }
}

@Test func actionJSONShape() throws {
    let data = try JSONEncoder().encode(ButtonAction.command(command: "blogrun", directory: "~/Documents/Workspace/blog"))
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: String]
    #expect(obj == ["kind": "command", "command": "blogrun", "directory": "~/Documents/Workspace/blog"])
}

@Test func nilDirectoryOmitsKey() throws {
    let data = try JSONEncoder().encode(ButtonAction.terminal(directory: nil))
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: String]
    #expect(obj == ["kind": "terminal"])
}

@Test func commandKeepOpenRoundTrip() throws {
    let action = ButtonAction.command(command: "uploadimg", directory: nil, keepOpen: false)
    let data = try JSONEncoder().encode(action)
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(obj["keepOpen"] as? Bool == false)
    #expect(try JSONDecoder().decode(ButtonAction.self, from: data) == action)
}

@Test func oldCommandWithoutKeepOpenStaysOpen() throws {
    // 이 값이 생기기 전에 저장된 버튼은 지금처럼 창을 유지한다
    let old = Data(#"{"kind":"command","command":"blogrun"}"#.utf8)
    #expect(try JSONDecoder().decode(ButtonAction.self, from: old) == .command(command: "blogrun", directory: nil, keepOpen: true))
}
