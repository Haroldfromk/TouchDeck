import Foundation
import Testing
@testable import DeckKit

@Test func pressRoundTrip() throws {
    let text = try ClientMessage.press(page: 0, index: 3).encoded()
    #expect(try ClientMessage.decode(text) == .press(page: 0, index: 3))
    #expect(text.contains("\"type\":\"press\""))
}

@Test func setButtonRoundTrip() throws {
    let m = ClientMessage.setButton(page: 1, index: 2, button: DeckButton(label: "blogrun", action: .command(command: "blogrun", directory: "~/Documents/Workspace/blog")))
    #expect(try ClientMessage.decode(m.encoded()) == m)
}

@Test func setVolumeUsesValueKey() throws {
    let text = try ClientMessage.setVolume(55).encoded()
    let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    #expect(obj["type"] as? String == "setVolume")
    #expect(obj["value"] as? Int == 55)
}

@Test func layoutRoundTripKeepsNullSlots() throws {
    var l = DeckLayout.empty
    try l.set(DeckButton(label: "X", action: .app(bundleId: "com.apple.dt.Xcode")), page: 0, index: 5)
    #expect(try ServerMessage.decode(ServerMessage.layout(l).encoded()) == .layout(l))
}

@Test func everyServerMessageRoundTrips() throws {
    let all: [ServerMessage] = [
        .needPairing(publicKey: "cHVi", nonce: "m1"), .pairingFailed(remaining: 3), .pairingLocked, .paired(proof: "ab"),
        .challenge(nonce: "n", proof: "cd"),
        .authorized, .unauthorized, .apps([AppInfo(name: "Xcode", bundleId: "com.apple.dt.Xcode", icon: "AAA")]),
        .pressResult(page: 0, index: 1, ok: false, message: "폴더 없음: /x"),
        .pressResult(page: 0, index: 1, ok: true, message: nil),
        .volume(value: 30, muted: true, available: true, keysAllowed: true),
        .volume(value: 0, muted: false, available: false, keysAllowed: false),
    ]
    for m in all { #expect(try ServerMessage.decode(m.encoded()) == m) }
}

@Test func everyClientMessageRoundTrips() throws {
    let all: [ClientMessage] = [
        .hello(deviceId: "d", deviceName: "Harold의 iPad", nonce: "c1"), .pair(publicKey: "cHVi", proof: "ab"), .auth(proof: "ab"),
        .getApps, .clearButton(page: 0, index: 0), .volumeKey(.up), .volumeKey(.down), .volumeKey(.mute),
        .typeKey(.digit(0)), .typeKey(.digit(7)), .typeKey(.tab), .typeKey(.delete), .typeKey(.enter),
    ]
    for m in all { #expect(try ClientMessage.decode(m.encoded()) == m) }
}

@Test func unknownTypeThrows() {
    #expect(throws: (any Error).self) { try ClientMessage.decode(#"{"type":"nope"}"#) }
}

@Test func volumeWithoutAvailableKeyMeansAvailable() throws {
    #expect(try ServerMessage.decode(#"{"type":"volume","value":40,"muted":false}"#) == .volume(value: 40, muted: false, available: true, keysAllowed: true))
}

@Test func pairMessageCarriesNoCode() throws {
    // 4자리 숫자는 네트워크로 나가지 않는다. 공개 키와 증명만 간다.
    let text = try ClientMessage.pair(publicKey: "cHVi", proof: "ab").encoded()
    #expect(text == #"{"proof":"ab","publicKey":"cHVi","type":"pair"}"#)
}

@Test func volumeKeyShape() throws {
    // 해피해킹 볼륨 키처럼 "올림/내림/음소거"만 보낸다. 지금 몇 %인지는 몰라도 된다.
    #expect(try ClientMessage.volumeKey(.up).encoded() == #"{"key":"up","type":"volumeKey"}"#)
}

@Test func typeKeyShape() throws {
    #expect(try ClientMessage.typeKey(.digit(7)).encoded() == #"{"key":"7","type":"typeKey"}"#)
    #expect(try ClientMessage.typeKey(.enter).encoded() == #"{"key":"enter","type":"typeKey"}"#)
}

@Test func typeKeyRejectsUnknownKey() {
    #expect(throws: (any Error).self) { try ClientMessage.decode(#"{"key":"a","type":"typeKey"}"#) }
    #expect(throws: (any Error).self) { try ClientMessage.decode(#"{"key":"10","type":"typeKey"}"#) }
}
