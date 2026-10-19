import Foundation
import Testing
@testable import DeckKit

@Test func commandArgumentsKeepQuotesIntact() {
    let args = AlacrittyCommand.openArguments(command: #"git commit -m "a b""#, directory: "/tmp")
    #expect(args == ["-na", "/Applications/Alacritty.app", "--args", "--working-directory", "/tmp",
                     "-e", "/bin/zsh", "-ic", #"git commit -m "a b"; exec zsh"#])
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

@Test func firstWordSkipsLeadingSpaces() {
    #expect(AlacrittyCommand.firstWord(of: "  blogrun --x") == "blogrun")
    #expect(AlacrittyCommand.firstWord(of: "   ") == nil)
}

@Test func lookupScriptQuotesName() {
    #expect(AlacrittyCommand.lookupScript(for: "blogrun") == "whence -- 'blogrun' >/dev/null")
    #expect(AlacrittyCommand.lookupScript(for: "it's") == #"whence -- 'it'\''s' >/dev/null"#)
}
