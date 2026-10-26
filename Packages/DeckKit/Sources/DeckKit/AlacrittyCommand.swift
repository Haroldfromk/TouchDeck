import Foundation

/// `/usr/bin/open`에 넘길 인자를 만든다. 인자 배열로 넘기니 셸 따옴표 처리가 필요 없다.
/// 명령 문자열은 zsh `-c`의 인자 하나로 통째로 들어간다.
public enum AlacrittyCommand {
    public static let appPath = "/Applications/Alacritty.app"
    /// 로그인(-l)이면서 대화형(-i). 로그인 항목으로 켜진 맥 앱은 PATH가 /usr/bin:/bin 정도라
    /// Homebrew 경로를 넣는 ~/.zprofile까지 읽어야 pngquant 같은 명령이 보인다. 별칭은 ~/.zshrc(-i)에서 온다
    public static let shellFlags = "-lic"

    /// - command: nil이면 빈 새 창. 있으면 대화형 zsh(`~/.zshrc`를 읽어 별칭이 먹는다)로 실행하고,
    ///   끝나도 창이 닫히지 않게 `exec zsh`로 셸을 이어 둔다.
    ///   명령은 작은따옴표로 감싸 `eval`에 넘긴다. 명령 끝의 `# 주석`이나 안 닫힌 따옴표가
    ///   뒤의 `exec zsh`까지 삼키면 명령이 끝나자마자 창이 닫히기 때문이다.
    /// keepOpen == false면 명령이 끝날 때 창도 닫힌다 (뒤에 exec zsh를 붙이지 않는다)
    public static func openArguments(command: String?, directory: String?, keepOpen: Bool = true) -> [String] {
        let dir = directory.map(expandTilde) ?? NSHomeDirectory()
        var args = ["-na", appPath, "--args", "--working-directory", dir]
        if let command {
            args += ["-e", "/bin/zsh", shellFlags, script(command: command, keepOpen: keepOpen)]
        }
        return args
    }

    /// 셸에 넘길 스크립트. 명령은 작은따옴표로 감싸 eval에 넘긴다(명령 끝 주석이나 안 닫힌 따옴표가 뒤를 삼키지 않게).
    /// 창을 남기면 뒤에 exec zsh를 붙여 셸을 이어 둔다. 실행 인자로 명령을 넘기는 터미널(Alacritty, Ghostty, WezTerm, kitty)이 같이 쓴다
    public static func script(command: String, keepOpen: Bool) -> String {
        let script = "eval \(singleQuoted(command))"
        return keepOpen ? "\(script); exec zsh" : script
    }

    /// 실행 전에 무엇을 확인할지.
    public enum Preflight: Equatable, Sendable {
        /// 명령이 비어 있다
        case empty
        /// 이 이름이 zsh에서 찾아지는지(별칭/함수/명령) 확인한다
        case lookup(String)
        /// 이 경로에 실행 파일이 있는지 확인한다
        case executable(String)
        /// 첫 단어를 제대로 자를 수 없어서 확인하지 않고 실행한다
        case skip
    }

    /// 따옴표, 변수, 괄호 같은 게 섞이면 공백으로 자른 단어가 zsh가 보는 단어와 다를 수 있다.
    private static let unparsable = Set(#""'`$\(){};|&<>*?"#)

    /// 앞의 `FOO=1` 같은 환경 변수는 건너뛰고, `./deploy.sh`처럼 경로 모양이면 지정 폴더 기준으로 본다.
    public static func preflight(command: String, directory: String?) -> Preflight {
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return .empty }
        let assignments = words.prefix { $0.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*=.*/) != nil }
        guard let word = words.dropFirst(assignments.count).first,
              !(assignments + [word]).contains(where: { $0.contains(where: unparsable.contains) }) else { return .skip }
        guard word.contains("/") else { return .lookup(word) }
        let path = expandTilde(word)
        let base = URL(filePath: directory.map(expandTilde) ?? NSHomeDirectory())
        return .executable((path.hasPrefix("/") ? URL(filePath: path) : base.appending(path: path)).standardized.path)
    }

    /// 명령 이름이 zsh에서 찾아지는지(별칭/함수/명령) 확인하는 스크립트.
    /// `zsh -ic '…' zsh 이름`처럼 위치 인자를 붙이면 해롤드의 ~/.zshrc 환경에서는 스크립트가
    /// 아예 실행되지 않았다. 그래서 이름을 작은따옴표로 감싸 스크립트 안에 직접 넣는다.
    public static func lookupScript(for name: String) -> String {
        "whence -- \(singleQuoted(name)) >/dev/null"
    }

    public static func expandTilde(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + path.dropFirst(1) }
        return path
    }

    public static func singleQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: #"'\''"#))'"
    }
}
