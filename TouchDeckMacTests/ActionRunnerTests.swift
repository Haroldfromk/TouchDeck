import DeckKit
import Foundation
import Testing
@testable import TouchDeck

@Test func missingDirectoryFailsWithReason() async {
    var r = ActionRunner.fake()
    r.directoryExists = { _ in false }
    let out = await r.run(.command(command: "blogrun", directory: "~/nope"))
    #expect(out.ok == false)
    #expect(out.message == "폴더 없음: \(NSHomeDirectory())/nope")
}

@Test func unknownCommandFailsWithReason() async {
    var r = ActionRunner.fake()
    r.commandExists = { _ in false }
    let out = await r.run(.command(command: "blogrn", directory: nil))
    #expect(out.ok == false)
    #expect(out.message == "blogrn을(를) 찾을 수 없음")
}

@Test func validCommandOpensAlacrittyWithArguments() async {
    let captured = Captured()
    var r = ActionRunner.fake()
    r.runOpen = { captured.args = $0 }
    let out = await r.run(.command(command: "blogrun", directory: "/tmp"))
    #expect(out.ok)
    #expect(captured.args == AlacrittyCommand.openArguments(command: "blogrun", directory: "/tmp"))
}

@Test func terminalOpensEmptyWindow() async {
    let captured = Captured()
    var r = ActionRunner.fake()
    r.runOpen = { captured.args = $0 }
    let out = await r.run(.terminal(directory: nil))
    #expect(out.ok)
    #expect(captured.args == AlacrittyCommand.openArguments(command: nil, directory: nil))
}

@Test func missingAlacrittyFails() async {
    var r = ActionRunner.fake()
    r.alacrittyInstalled = { false }
    let out = await r.run(.terminal(directory: nil))
    #expect(out.ok == false)
    #expect(out.message == "Alacritty가 설치되어 있지 않음")
}

@Test func missingAppFails() async {
    var r = ActionRunner.fake()
    r.openApp = { _ in throw ActionRunner.AppNotFound() }
    let out = await r.run(.app(bundleId: "com.example.none"))
    #expect(out.ok == false)
    #expect(out.message == "앱을 찾을 수 없음: com.example.none")
}

@Test func emptyCommandFails() async {
    let out = await ActionRunner.fake().run(.command(command: "   ", directory: nil))
    #expect(out.ok == false)
    #expect(out.message == "명령이 비어 있음")
}

final class Captured: @unchecked Sendable { var args: [String] = [] }
