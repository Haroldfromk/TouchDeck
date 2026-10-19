import Foundation

/// `/usr/bin/open`에 넘길 인자를 만든다. 인자 배열로 넘기니 셸 따옴표 처리가 필요 없다.
/// 명령 문자열은 zsh `-c`의 인자 하나로 통째로 들어간다.
public enum AlacrittyCommand {
    public static let appPath = "/Applications/Alacritty.app"

    /// - command: nil이면 빈 새 창. 있으면 대화형 zsh(`~/.zshrc`를 읽어 별칭이 먹는다)로 실행하고,
    ///   끝나도 창이 닫히지 않게 `exec zsh`로 셸을 이어 둔다.
    public static func openArguments(command: String?, directory: String?) -> [String] {
        let dir = directory.map(expandTilde) ?? NSHomeDirectory()
        var args = ["-na", appPath, "--args", "--working-directory", dir]
        if let command {
            args += ["-e", "/bin/zsh", "-ic", "\(command); exec zsh"]
        }
        return args
    }

    public static func firstWord(of command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    public static func expandTilde(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + path.dropFirst(1) }
        return path
    }
}
