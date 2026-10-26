import Foundation
import Testing
@testable import DeckKit

@Test func bundleIdsMatchSpec() {
    #expect(TerminalApp.allCases.map(\.bundleId) == ["com.apple.Terminal", "org.alacritty", "com.googlecode.iterm2",
                                                     "com.mitchellh.ghostty", "com.github.wez.wezterm", "net.kovidgoyal.kitty"])
    #expect(TerminalApp.allCases.filter(\.usesAppleScript) == [.terminal, .iterm2])
}

@Test func alacrittyLaunchMatchesExisting() {
    let command = #"git commit -m "a b""#
    #expect(TerminalApp.alacritty.launch(appPath: AlacrittyCommand.appPath, command: command, directory: "/tmp", keepOpen: true)
            == .open(AlacrittyCommand.openArguments(command: command, directory: "/tmp")))
    #expect(TerminalApp.alacritty.launch(appPath: AlacrittyCommand.appPath, command: nil, directory: nil, keepOpen: true)
            == .open(AlacrittyCommand.openArguments(command: nil, directory: nil)))
}

@Test func argumentTerminalsPassTheShellScript() {
    let script = AlacrittyCommand.script(command: "blogrun", keepOpen: true)
    #expect(TerminalApp.ghostty.launch(appPath: "/A/Ghostty.app", command: "blogrun", directory: "/tmp", keepOpen: true)
            == .open(["-na", "/A/Ghostty.app", "--args", "--working-directory=/tmp", "-e", "/bin/zsh", "-lic", script]))
    #expect(TerminalApp.wezterm.launch(appPath: "/A/WezTerm.app", command: "blogrun", directory: "/tmp", keepOpen: true)
            == .open(["-na", "/A/WezTerm.app", "--args", "start", "--cwd", "/tmp", "--", "/bin/zsh", "-lic", script]))
    #expect(TerminalApp.kitty.launch(appPath: "/A/kitty.app", command: "blogrun", directory: "/tmp", keepOpen: true)
            == .open(["-na", "/A/kitty.app", "--args", "--directory", "/tmp", "/bin/zsh", "-lic", script]))
    #expect(TerminalApp.kitty.launch(appPath: "/A/kitty.app", command: nil, directory: "/tmp", keepOpen: true)
            == .open(["-na", "/A/kitty.app", "--args", "--directory", "/tmp"]))
}

@Test func appleScriptTextKeepsQuotesIntact() {
    let command = #"echo "it's" \ 한글 👍🏽"#
    guard case .appleScript(let lines, let text) = TerminalApp.terminal.launch(appPath: "/T", command: command, directory: "/tmp/my 'dir'", keepOpen: false) else {
        Issue.record("AppleScript가 아님"); return
    }
    #expect(text == "cd " + AlacrittyCommand.singleQuoted("/tmp/my 'dir'") + " && eval " + AlacrittyCommand.singleQuoted(command) + "; exit")
    #expect(!lines.joined().contains("echo"))
    #expect(lines.joined(separator: "\n").contains("item 1 of argv"))
}

@Test func appleScriptEmptyWindowOnlyChangesFolder() {
    guard case .appleScript(_, let text) = TerminalApp.iterm2.launch(appPath: "/I", command: nil, directory: "/tmp", keepOpen: true) else {
        Issue.record("AppleScript가 아님"); return
    }
    #expect(text == "cd '/tmp'")
}

/// 보낼 글을 실제 zsh로 돌려서, 명령 끝 주석이나 안 닫힌 따옴표가 있어도 뒤가 실행되는지 본다(창을 남길 때)
@Test(arguments: ["echo hi # 주석", #"echo "abc"#, "echo 'it"])
func appleScriptTextStillRunsAfterBrokenCommand(_ command: String) throws {
    guard case .appleScript(_, let text) = TerminalApp.terminal.launch(appPath: "/T", command: command, directory: "/tmp", keepOpen: true) else {
        Issue.record("AppleScript가 아님"); return
    }
    let process = Process()
    process.executableURL = URL(filePath: "/bin/zsh")
    process.arguments = ["-fc", text + "; echo AFTER"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(output.hasSuffix("AFTER\n"))
}

@Test func defaultPrefersAlacrittyThenTerminal() {
    #expect(TerminalApp.choose(saved: nil, installed: [.terminal, .alacritty]) == .use(.alacritty))
    #expect(TerminalApp.choose(saved: nil, installed: [.terminal]) == .use(.terminal))
    #expect(TerminalApp.choose(saved: nil, installed: []) == .use(.terminal))
}

@Test func savedInstalledIsUsed() {
    #expect(TerminalApp.choose(saved: "com.apple.Terminal", installed: [.terminal, .alacritty]) == .use(.terminal))
}

@Test func savedButRemovedIsMissing() {
    #expect(TerminalApp.choose(saved: "com.googlecode.iterm2", installed: [.terminal, .alacritty]) == .missing(.iterm2))
}

@Test func unknownSavedFallsBackToDefault() {
    #expect(TerminalApp.choose(saved: "dev.warp.Warp-Stable", installed: [.terminal]) == .use(.terminal))
}
