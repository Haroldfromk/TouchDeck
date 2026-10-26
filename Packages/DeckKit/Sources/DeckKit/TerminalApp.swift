import Foundation

/// 명령 버튼과 새 터미널 버튼을 열 터미널. 맥 메뉴에서 설치된 것 중에 고른다.
/// 터미널마다 명령을 넘기는 방법이 달라서, 방법을 맞춰 둔 이 목록 안에서만 고를 수 있다
public enum TerminalApp: String, CaseIterable, Sendable {
    case terminal = "com.apple.Terminal"
    case alacritty = "org.alacritty"
    case iterm2 = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"
    case wezterm = "com.github.wez.wezterm"
    case kitty = "net.kovidgoyal.kitty"

    public var bundleId: String { rawValue }

    public var name: String {
        switch self {
        case .terminal: "기본 터미널"
        case .alacritty: "Alacritty"
        case .iterm2: "iTerm2"
        case .ghostty: "Ghostty"
        case .wezterm: "WezTerm"
        case .kitty: "kitty"
        }
    }

    /// 새 창에 셸이 이미 떠 있고, AppleScript로 거기에 글을 보내 실행하는 터미널
    public var usesAppleScript: Bool { self == .terminal || self == .iterm2 }

    /// 맥이 실제로 할 일. 명령 글자는 AppleScript 소스에 넣지 않고 text로 따로 넘긴다
    public func launch(appPath: String, command: String?, directory: String?, keepOpen: Bool) -> TerminalLaunch {
        let dir = directory.map(AlacrittyCommand.expandTilde) ?? NSHomeDirectory()
        let shell = command.map { ["/bin/zsh", AlacrittyCommand.shellFlags, AlacrittyCommand.script(command: $0, keepOpen: keepOpen)] }
        switch self {
        case .alacritty:
            var args = ["-na", appPath, "--args", "--working-directory", dir]
            if let shell { args += ["-e"] + shell }
            return .open(args)
        case .ghostty:
            var args = ["-na", appPath, "--args", "--working-directory=\(dir)"]
            if let shell { args += ["-e"] + shell }
            return .open(args)
        case .wezterm:
            var args = ["-na", appPath, "--args", "start", "--cwd", dir]
            if let shell { args += ["--"] + shell }
            return .open(args)
        case .kitty:
            var args = ["-na", appPath, "--args", "--directory", dir]
            if let shell { args += shell }
            return .open(args)
        case .terminal, .iterm2:
            // 새 창의 셸은 사용자의 로그인 셸이라 별칭과 Homebrew 경로가 이미 잡혀 있다
            var text = "cd \(AlacrittyCommand.singleQuoted(dir))"
            if let command {
                text += " && eval \(AlacrittyCommand.singleQuoted(command))"
                if !keepOpen { text += "; exit" }
            }
            return .appleScript(lines: self == .terminal ? Self.terminalScript : Self.itermScript, text: text)
        }
    }

    /// 꺼져 있던 기본 터미널을 AppleScript로 열면 시작 창과 명령 창이 따로 두 개 뜬다.
    /// 그래서 꺼져 있었으면 시작 창이 생길 때까지 기다렸다가 그 창(window 1)에 보낸다
    static let terminalScript = [
        "on run argv",
        "set wasRunning to application \"Terminal\" is running",
        "tell application \"Terminal\"",
        "activate",
        "if wasRunning then",
        "do script (item 1 of argv)",
        "else",
        "repeat 20 times",
        "if (count of windows) > 0 then exit repeat",
        "delay 0.1",
        "end repeat",
        "do script (item 1 of argv) in window 1",
        "end if",
        "end tell",
        "end run",
    ]

    static let itermScript = [
        "on run argv",
        "tell application \"iTerm\"",
        "activate",
        "set newWindow to (create window with default profile)",
        "tell current session of newWindow to write text (item 1 of argv)",
        "end tell",
        "end run",
    ]

    /// 기억된 값(번들 ID)과 설치된 터미널로 무엇을 쓸지 정한다.
    /// 기억된 터미널이 지워졌으면 몰래 바꾸지 않고 missing. 기억이 없거나 모르는 값이면 Alacritty, 없으면 기본 터미널
    public static func choose(saved: String?, installed: Set<TerminalApp>) -> TerminalChoice {
        if let saved, let app = TerminalApp(rawValue: saved) {
            return installed.contains(app) ? .use(app) : .missing(app)
        }
        return .use(installed.contains(.alacritty) ? .alacritty : .terminal)
    }
}

public enum TerminalLaunch: Equatable, Sendable {
    /// /usr/bin/open에 넘길 인자
    case open([String])
    /// osascript에 줄마다 -e로 넘길 소스와, 마지막 인자(argv의 첫째)로 넘길 글
    case appleScript(lines: [String], text: String)
}

public enum TerminalChoice: Equatable, Sendable {
    case use(TerminalApp)
    case missing(TerminalApp)
}
