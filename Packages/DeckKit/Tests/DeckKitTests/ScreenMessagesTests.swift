import Foundation
import Testing
@testable import DeckKit

// MARK: - 화면 메시지

@Test func screenClientMessagesRoundTrip() throws {
    let all: [ClientMessage] = [
        .listDisplays, .startScreen(displayId: 69_734_208, maxSide: 1920), .stopScreen, .requestKeyframe,
        .pointer(PointerEvent(kind: .click, x: 0.25, y: 0.75)),
        .pointer(PointerEvent(kind: .scroll, x: 0.5, y: 0.5, dx: -3, dy: 12.5)),
        .pointer(PointerEvent(kind: .down, x: 0, y: 1)), .pointer(PointerEvent(kind: .move, x: 0.1, y: 0.2)),
        .pointer(PointerEvent(kind: .up, x: 0.1, y: 0.2)), .pointer(PointerEvent(kind: .rightClick, x: 0.9, y: 0.1)),
    ]
    for m in all { #expect(try ClientMessage.decode(m.encoded()) == m) }
}

@Test func pointerIsFlatJSON() throws {
    let text = try ClientMessage.pointer(PointerEvent(kind: .rightClick, x: 0.5, y: 0.25)).encoded()
    let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    #expect(obj["type"] as? String == "pointer")
    #expect(obj["kind"] as? String == "rightClick")
    #expect(obj["x"] as? Double == 0.5)
    #expect(obj["y"] as? Double == 0.25)
}

@Test func screenServerMessagesRoundTrip() throws {
    let all: [ServerMessage] = [
        .displays([DisplayInfo(id: 1, name: "LG ULTRAWIDE", width: 3440, height: 1440, thumbnail: "/9j/"),
                   DisplayInfo(id: 2, name: "내장 디스플레이", width: 1512, height: 982, thumbnail: "")]),
        .displays([]),
        .screenStarted(displayId: 1, width: 1920, height: 804),
        .screenStatus(.ok, message: nil), .screenStatus(.notAllowed, message: "맥 메뉴에서 화면 보기를 켜 주세요"),
        .screenStatus(.noPermission, message: nil), .screenStatus(.busy, message: "Harold의 iPhone"),
        .screenStatus(.locked, message: nil), .screenStatus(.stopped, message: nil),
    ]
    for m in all { #expect(try ServerMessage.decode(m.encoded()) == m) }
}

// MARK: - 허락한 기기의 화면 허용

@Test func oldTrustedDeviceJSONReadsAsScreenNotAllowed() throws {
    // 화면 기능 전에 저장한 config.json에는 screenAllowed가 없다
    let old = #"{"id":"d1","name":"iPad","token":"dG9r"}"#
    let device = try JSONDecoder().decode(TrustedDevice.self, from: Data(old.utf8))
    #expect(device == TrustedDevice(id: "d1", name: "iPad", token: "dG9r"))
    #expect(device.screenAllowed == false)
}

@Test func screenAllowedSurvivesSave() throws {
    var device = TrustedDevice(id: "d1", name: "iPad", token: "dG9r")
    device.screenAllowed = true
    let back = try JSONDecoder().decode(TrustedDevice.self, from: JSONEncoder().encode(device))
    #expect(back.screenAllowed)
}

@Test func authoritySetsScreenAllowedPerDevice() {
    var authority = PairingAuthority(trusted: [TrustedDevice(id: "a", name: "iPad", token: "dA=="),
                                               TrustedDevice(id: "b", name: "iPhone", token: "dA==")])
    authority.setScreenAllowed(true, deviceId: "b")
    #expect(authority.trusted.first { $0.id == "a" }?.screenAllowed == false)
    #expect(authority.trusted.first { $0.id == "b" }?.screenAllowed == true)
    #expect(authority.isScreenAllowed(deviceId: "b"))
    #expect(!authority.isScreenAllowed(deviceId: "a"))
    #expect(!authority.isScreenAllowed(deviceId: "nobody"))
}

// MARK: - 화면을 보여줘도 되는지

@Test func screenAccessOkWhenAllowedAndFree() {
    #expect(ScreenAccess.decide(allowed: true, permission: true, locked: false, viewer: nil, requester: "a") == .ok)
}

@Test func screenAccessNotAllowedComesFirst() {
    // 허용 안 된 기기에는 권한이나 잠김 상태도 알려 주지 않는다
    #expect(ScreenAccess.decide(allowed: false, permission: false, locked: true, viewer: "b", requester: "a") == .notAllowed)
}

@Test func screenAccessNeedsScreenRecordingPermission() {
    #expect(ScreenAccess.decide(allowed: true, permission: false, locked: false, viewer: nil, requester: "a") == .noPermission)
}

@Test func screenAccessRefusesWhileLocked() {
    #expect(ScreenAccess.decide(allowed: true, permission: true, locked: true, viewer: nil, requester: "a") == .locked)
}

@Test func screenAccessOneViewerAtATime() {
    #expect(ScreenAccess.decide(allowed: true, permission: true, locked: false, viewer: "b", requester: "a") == .busy)
}

@Test func screenAccessSameDeviceCanTakeOver() {
    // 같은 기기가 다시 붙었으면(앞 접속이 반쯤 죽었어도) 이어서 본다
    #expect(ScreenAccess.decide(allowed: true, permission: true, locked: false, viewer: "a", requester: "a") == .ok)
}
