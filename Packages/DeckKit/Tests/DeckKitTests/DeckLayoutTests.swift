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

private func b(_ s: String) -> DeckButton { DeckButton(label: s, action: .terminal(directory: nil)) }

@Test func moveIntoEmptySlot() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 0)
    try l.move(fromPage: 0, fromIndex: 0, toPage: 0, toIndex: 5, expecting: b("a"))
    #expect(l.pages[0].buttons[0] == nil)
    #expect(l.pages[0].buttons[5] == b("a"))
}

@Test func moveOntoFilledSlotSwaps() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 0)
    try l.set(b("b"), page: 0, index: 1)
    try l.move(fromPage: 0, fromIndex: 0, toPage: 0, toIndex: 1, expecting: b("a"))
    #expect(l.pages[0].buttons[0] == b("b"))
    #expect(l.pages[0].buttons[1] == b("a"))
}

@Test func moveToSameSlotChangesNothing() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 3)
    let before = l
    try l.move(fromPage: 0, fromIndex: 3, toPage: 0, toIndex: 3, expecting: b("a"))
    #expect(l == before)
}

@Test func moveAcrossPages() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 0)
    try l.set(b("b"), page: 1, index: 4)
    try l.move(fromPage: 1, fromIndex: 4, toPage: 0, toIndex: 0, expecting: b("b"))
    #expect(l.pages[0].buttons[0] == b("b"))
    #expect(l.pages[1].buttons[4] == b("a"))
}

@Test func moveToTrailingEmptyPageAddsPage() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 0)          // pages: [a], []
    try l.set(b("b"), page: 0, index: 1)
    try l.move(fromPage: 0, fromIndex: 1, toPage: 1, toIndex: 0, expecting: b("b"))
    #expect(l.pages.count == 3)
    #expect(l.pages[1].buttons[0] == b("b"))
    #expect(l.pages[2].isEmpty)
}

@Test func moveOffLastFilledPageTrimsTrailing() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 0)
    try l.set(b("b"), page: 1, index: 0)          // pages: [a], [b], []
    try l.move(fromPage: 1, fromIndex: 0, toPage: 0, toIndex: 1, expecting: b("b"))
    #expect(l.pages.count == 2)
    #expect(l.pages[1].isEmpty)
}

@Test func moveEmptyingMiddlePageKeepsIt() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 0)
    try l.set(b("b"), page: 1, index: 0)
    try l.set(b("c"), page: 2, index: 0)          // pages: [a], [b], [c], []
    try l.move(fromPage: 1, fromIndex: 0, toPage: 0, toIndex: 1, expecting: b("b"))
    #expect(l.pages.count == 4)
    #expect(l.pages[1].isEmpty)
}

@Test func moveRejectsStaleButton() throws {
    var l = DeckLayout.empty
    try l.set(b("a"), page: 0, index: 0)
    let before = l
    #expect(throws: LayoutError.stale) {
        try l.move(fromPage: 0, fromIndex: 0, toPage: 0, toIndex: 1, expecting: b("other"))
    }
    #expect(throws: LayoutError.stale) {
        try l.move(fromPage: 0, fromIndex: 2, toPage: 0, toIndex: 1, expecting: b("a"))   // 빈 칸
    }
    #expect(l == before)
}

@Test func moveOutOfRangeThrows() {
    var l = DeckLayout.empty
    #expect(throws: LayoutError.outOfRange) {
        try l.move(fromPage: 0, fromIndex: 0, toPage: 3, toIndex: 0, expecting: b("a"))
    }
    #expect(throws: LayoutError.outOfRange) {
        try l.move(fromPage: 0, fromIndex: 12, toPage: 0, toIndex: 0, expecting: b("a"))
    }
}
