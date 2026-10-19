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
        .needPairing, .pairingFailed(remaining: 3), .paired(token: "t"), .challenge(nonce: "n"),
        .authorized, .unauthorized, .apps([AppInfo(name: "Xcode", bundleId: "com.apple.dt.Xcode", icon: "AAA")]),
        .pressResult(page: 0, index: 1, ok: false, message: "폴더 없음: /x"),
        .pressResult(page: 0, index: 1, ok: true, message: nil),
        .volume(value: 30, muted: true, available: true),
        .volume(value: 0, muted: false, available: false),
    ]
    for m in all { #expect(try ServerMessage.decode(m.encoded()) == m) }
}

@Test func everyClientMessageRoundTrips() throws {
    let all: [ClientMessage] = [
        .hello(deviceId: "d", deviceName: "Harold의 iPad"), .pair(code: "0042"), .auth(signature: "ab"),
        .getApps, .clearButton(page: 0, index: 0),
    ]
    for m in all { #expect(try ClientMessage.decode(m.encoded()) == m) }
}

@Test func unknownTypeThrows() {
    #expect(throws: (any Error).self) { try ClientMessage.decode(#"{"type":"nope"}"#) }
}

@Test func volumeWithoutAvailableKeyMeansAvailable() throws {
    #expect(try ServerMessage.decode(#"{"type":"volume","value":40,"muted":false}"#) == .volume(value: 40, muted: false, available: true))
}
