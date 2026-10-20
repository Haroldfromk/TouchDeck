import Foundation
import Testing
@testable import DeckKit

@Test func commandArgumentsKeepQuotesIntact() {
    let args = AlacrittyCommand.openArguments(command: #"git commit -m "a b""#, directory: "/tmp")
    #expect(args == ["-na", "/Applications/Alacritty.app", "--args", "--working-directory", "/tmp",
                     "-e", "/bin/zsh", "-lic", #"eval 'git commit -m "a b"'; exec zsh"#])
}

/// 로그인 항목으로 켜진 맥 앱은 PATH가 /usr/bin:/bin 정도라, Homebrew 경로를 넣는 ~/.zprofile까지 읽어야 한다(-l).
/// 대화형(-i)이어야 ~/.zshrc의 별칭도 보인다.
@Test func shellReadsLoginProfileAndZshrc() {
    #expect(AlacrittyCommand.shellFlags == "-lic")
}

/// 명령 끝의 # 주석이나 안 닫힌 따옴표가 뒤의 exec zsh를 삼키면 명령이 끝나자마자 창이 닫힌다.
/// 실제 zsh로 돌려서 명령 다음 줄이 실행되는지 본다 (exec zsh 대신 echo로 바꿔서).
@Test(arguments: ["echo hi # 주석", #"echo "abc"#, "echo 'it"])
func shellStillContinuesAfterBrokenCommand(_ command: String) throws {
    let script = try #require(AlacrittyCommand.openArguments(command: command, directory: "/tmp").last)
    let process = Process()
    process.executableURL = URL(filePath: "/bin/zsh")
    process.arguments = ["-fc", script.replacingOccurrences(of: "exec zsh", with: "echo AFTER")]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(output.hasSuffix("AFTER\n"))
}

@Test func newWindowArgumentsDefaultToHome() {
    #expect(AlacrittyCommand.openArguments(command: nil, directory: nil)
            == ["-na", "/Applications/Alacritty.app", "--args", "--working-directory", NSHomeDirectory()])
}

@Test func tildeExpands() {
    #expect(AlacrittyCommand.expandTilde("~/Documents") == NSHomeDirectory() + "/Documents")
    #expect(AlacrittyCommand.expandTilde("~") == NSHomeDirectory())
    #expect(AlacrittyCommand.expandTilde("/tmp") == "/tmp")
}

@Test func preflightLooksUpPlainName() {
    #expect(AlacrittyCommand.preflight(command: "  blogrun --x", directory: nil) == .lookup("blogrun"))
}

@Test func preflightSkipsEnvironmentAssignments() {
    #expect(AlacrittyCommand.preflight(command: "FOO=1 BAR=x npm start", directory: nil) == .lookup("npm"))
    #expect(AlacrittyCommand.preflight(command: "FOO=1", directory: nil) == .skip)
}

@Test func preflightChecksPathAgainstChosenFolder() {
    #expect(AlacrittyCommand.preflight(command: "./deploy.sh prod", directory: "/tmp/site")
            == .executable("/tmp/site/deploy.sh"))
    #expect(AlacrittyCommand.preflight(command: "bin/run", directory: "~/app")
            == .executable(NSHomeDirectory() + "/app/bin/run"))
    #expect(AlacrittyCommand.preflight(command: "./x", directory: nil)
            == .executable(NSHomeDirectory() + "/x"))
    #expect(AlacrittyCommand.preflight(command: "/usr/bin/env", directory: "/tmp") == .executable("/usr/bin/env"))
    #expect(AlacrittyCommand.preflight(command: "~/bin/go", directory: "/tmp") == .executable(NSHomeDirectory() + "/bin/go"))
}

/// 따옴표, 변수, 괄호 같은 게 섞이면 첫 단어를 제대로 못 자르니 확인하지 않고 그냥 실행한다.
@Test(arguments: [#""my tool" --x"#, "'npm' start", "$EDITOR a.txt", "(cd a; make)", #"FOO="a b" npm start"#, "{ ls }", #"a\ b"#])
func preflightSkipsWhatItCannotParse(_ command: String) {
    #expect(AlacrittyCommand.preflight(command: command, directory: nil) == .skip)
}

@Test func preflightOfBlankCommandIsEmpty() {
    #expect(AlacrittyCommand.preflight(command: "   ", directory: nil) == .empty)
}

@Test func lookupScriptQuotesName() {
    #expect(AlacrittyCommand.lookupScript(for: "blogrun") == "whence -- 'blogrun' >/dev/null")
    #expect(AlacrittyCommand.lookupScript(for: "it's") == #"whence -- 'it'\''s' >/dev/null"#)
}

@Test func closeWhenDoneDropsTrailingShell() {
    // 금방 끝나는 명령(uploadimg 등)은 끝나면 창이 닫히게: 뒤에 exec zsh를 붙이지 않는다
    let args = AlacrittyCommand.openArguments(command: "uploadimg", directory: "/tmp", keepOpen: false)
    #expect(args.last == "eval 'uploadimg'")
}

@Test func keepOpenIsDefault() {
    #expect(AlacrittyCommand.openArguments(command: "blogrun", directory: "/tmp")
            == AlacrittyCommand.openArguments(command: "blogrun", directory: "/tmp", keepOpen: true))
}
