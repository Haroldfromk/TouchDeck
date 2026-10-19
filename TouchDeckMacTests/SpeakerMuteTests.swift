import Foundation
import Testing
@testable import TouchDeck

@Test func mutesSystemOutput() {
    #expect(SpeakerMute.plan(source: .system, alreadyMuted: false) == .muted(.init(kind: .system, name: nil)))
}

@Test func mutesMonitorThroughBetterDisplay() {
    #expect(SpeakerMute.plan(source: .betterDisplay(name: "LG ULTRAWIDE"), alreadyMuted: false)
            == .muted(.init(kind: .betterDisplay, name: "LG ULTRAWIDE")))
}

@Test func alreadyMutedIsLeftAlone() {
    #expect(SpeakerMute.plan(source: .system, alreadyMuted: true) == .alreadyMuted)
}

@Test func unknownOutputCannotMute() {
    #expect(SpeakerMute.plan(source: .none, alreadyMuted: false) == .cannotMute)
}

@Test func leftoverRecordIsRestoredOnLaunch() throws {
    let record = SpeakerMute.Record(kind: .betterDisplay, name: "LG ULTRAWIDE")
    #expect(SpeakerMute.restoreOnLaunch(stored: try JSONEncoder().encode(record)) == record)
    #expect(SpeakerMute.restoreOnLaunch(stored: nil) == nil)
    #expect(SpeakerMute.restoreOnLaunch(stored: Data("x".utf8)) == nil)
}
