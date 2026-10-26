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

@Test func missingTerminalFailsWithName() async {
    var r = ActionRunner.fake()
    r.resolveTerminal = { .missing(.iterm2) }
    let out = await r.run(.terminal(directory: nil))
    #expect(out.ok == false)
    #expect(out.message == "iTerm2을(를) 찾을 수 없어요. 맥 메뉴에서 다른 터미널을 고르세요")
}

@Test func appleScriptTerminalRunsScript() async {
    let captured = CapturedScript()
    var r = ActionRunner.fake()
    r.resolveTerminal = { .ready(.terminal, appPath: "/System/Applications/Utilities/Terminal.app") }
    r.runScript = { captured.lines = $0; captured.text = $1 }
    r.runOpen = { _ in Issue.record("open을 부르면 안 됨") }
    let out = await r.run(.command(command: "blogrun", directory: "/tmp"))
    #expect(out.ok)
    #expect(captured.text == "cd '/tmp' && eval 'blogrun'")
}

@Test func appleScriptFailureExplainsAutomation() async {
    var r = ActionRunner.fake()
    r.resolveTerminal = { .ready(.terminal, appPath: "/T") }
    r.runScript = { _, _ in throw NSError(domain: "osascript", code: 1) }
    let out = await r.run(.terminal(directory: nil))
    #expect(out.ok == false)
    #expect(out.message == "기본 터미널을(를) 열지 못했어요. 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 TouchDeck을 켜 주세요")
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

@Test func environmentPrefixIsSkippedBeforeLookup() async {
    let looked = Captured()
    var r = ActionRunner.fake()
    r.commandExists = { looked.args.append($0); return true }
    let out = await r.run(.command(command: "FOO=1 npm start", directory: nil))
    #expect(out.ok)
    #expect(looked.args == ["npm"])
}

@Test func pathCommandIsCheckedInChosenFolder() async {
    let checked = Captured()
    var r = ActionRunner.fake()
    r.commandExists = { _ in Issue.record("경로 모양은 zsh에 묻지 않는다"); return false }
    r.isExecutable = { checked.args.append($0); return false }
    let out = await r.run(.command(command: "./deploy.sh prod", directory: "/tmp/site"))
    #expect(out.ok == false)
    #expect(out.message == "실행 파일 없음: /tmp/site/deploy.sh")
    #expect(checked.args == ["/tmp/site/deploy.sh"])
}

@Test func existingPathCommandRuns() async {
    var r = ActionRunner.fake()
    r.isExecutable = { _ in true }
    let out = await r.run(.command(command: "./deploy.sh", directory: "/tmp"))
    #expect(out.ok)
}

@Test func unparsableCommandRunsWithoutCheck() async {
    var r = ActionRunner.fake()
    r.commandExists = { _ in false }
    let out = await r.run(.command(command: #""my tool" --x"#, directory: nil))
    #expect(out.ok)
}

/// ~/.zshrc가 멈추면 확인도 같이 멈춘다. 시간 제한을 넘기면 nil로 알려 준다.
@Test(.timeLimit(.minutes(1)))
func processTimesOut() throws {
    let start = ContinuousClock.now
    #expect(try runProcess("/bin/sleep", ["5"], timeout: .milliseconds(300)) == nil)
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(try runProcess("/usr/bin/false", [], timeout: .seconds(3)) == 1)
}

final class Captured: @unchecked Sendable { var args: [String] = [] }

@Test func closeWhenDonePassesThrough() async {
    let captured = Captured()
    var r = ActionRunner.fake()
    r.runOpen = { captured.args = $0 }
    _ = await r.run(.command(command: "uploadimg", directory: "/tmp", keepOpen: false))
    #expect(captured.args.last == "eval 'uploadimg'")
}

final class CapturedScript: @unchecked Sendable {
    var lines: [String] = []
    var text: String?
}
