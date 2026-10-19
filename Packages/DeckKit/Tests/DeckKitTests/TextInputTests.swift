import Foundation
import Testing
@testable import DeckKit

// MARK: - 글자 입력 메시지

@Test func typeTextAndPressKeyRoundTrip() throws {
    for m: ClientMessage in [.typeText(text: "검색어 abc"), .pressKey(.shiftTab), .pressKey(.controlC)] {
        #expect(try ClientMessage.decode(m.encoded()) == m)
    }
}

@Test func unknownKeyNameFailsToDecode() {
    #expect(throws: (any Error).self) { try ClientMessage.decode(#"{"type":"pressKey","key":"commandQ"}"#) }
}

// MARK: - 입력 정리와 나누기

@Test func cleanTurnsLineBreaksIntoSpaces() {
    #expect(TextInput.clean("a\nb\r\nc\rd\te") == "a b c d e")
}

@Test func cleanCutsAtTwoThousandCharacters() {
    let long = String(repeating: "가", count: 2100)
    #expect(TextInput.clean(long).count == 2000)
    let emoji = String(repeating: "a", count: 1999) + "👍🏽👍🏽"
    #expect(TextInput.clean(emoji) == String(repeating: "a", count: 1999) + "👍🏽")
}

@Test func chunksStayUnderTwentyUTF16() {
    let text = String(repeating: "한글", count: 25)   // 50글자, UTF-16 50
    let chunks = TextInput.chunks(text)
    #expect(chunks.joined() == text)
    #expect(chunks.allSatisfy { $0.utf16.count <= 20 })
    #expect(chunks.count == 3)
}

@Test func chunksNeverSplitACharacter() {
    let text = String(repeating: "a", count: 19) + "👍🏽"   // 👍🏽는 UTF-16 4개
    #expect(TextInput.chunks(text) == [String(repeating: "a", count: 19), "👍🏽"])
}

@Test func emptyTextHasNoChunks() {
    #expect(TextInput.chunks("") == [])
}

// MARK: - 기능 번호

@Test func helloCarriesProtocol() throws {
    let m = ClientMessage.hello(deviceId: "d", deviceName: "iPad", nonce: "n", protocolVersion: 2)
    #expect(try ClientMessage.decode(m.encoded()) == m)
}

@Test func helloWithoutProtocolIsOne() throws {
    let old = #"{"type":"hello","deviceId":"d","deviceName":"iPad","nonce":"n"}"#
    #expect(try ClientMessage.decode(old) == .hello(deviceId: "d", deviceName: "iPad", nonce: "n", protocolVersion: 1))
}

@Test func authorizedCarriesProtocol() throws {
    #expect(try ServerMessage.decode(ServerMessage.authorized(protocolVersion: 2).encoded()) == .authorized(protocolVersion: 2))
}

@Test func authorizedWithoutProtocolIsOne() throws {
    #expect(try ServerMessage.decode(#"{"type":"authorized"}"#) == .authorized(protocolVersion: 1))
}
