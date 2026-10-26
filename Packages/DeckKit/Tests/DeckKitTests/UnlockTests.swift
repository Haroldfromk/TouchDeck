import Foundation
import Network
import Testing
@testable import DeckKit

// MARK: - 메시지와 기능 번호

@Test func unlockMessagesRoundTrip() throws {
    for message in [ServerMessage.lockState(locked: true, unlockAllowed: false), .unlockResult(.wrongPassword)] {
        #expect(try ServerMessage.decode(message.encoded()) == message)
    }
    #expect(try ClientMessage.decode(ClientMessage.unlock(password: "a").encoded()) == .unlock(password: "a"))
}

@Test func unlockPasswordRoundTripsAnyCharacters() throws {
    let password = #"p"a\ss 한글 👍🏽"#
    #expect(try ClientMessage.decode(ClientMessage.unlock(password: password).encoded()) == .unlock(password: password))
}

@Test func oldTrustedDeviceHasUnlockOff() throws {
    let json = #"{"id":"a","name":"iPhone","token":"t","screenAllowed":true}"#
    #expect(try JSONDecoder().decode(TrustedDevice.self, from: Data(json.utf8)).unlockAllowed == false)
}

@Test func unlockNeedsProtocolFour() {
    #expect(DeckProtocol.unlock == 4)
    #expect(DeckProtocol.current >= DeckProtocol.unlock)
}

@Test func unlockAllowedFollowsSetter() {
    var authority = PairingAuthority(trusted: [TrustedDevice(id: "a", name: "iPad", token: "dA=="),
                                               TrustedDevice(id: "b", name: "iPhone", token: "dA==")])
    authority.setUnlockAllowed(true, deviceId: "b")
    #expect(authority.isUnlockAllowed(deviceId: "b"))
    #expect(!authority.isUnlockAllowed(deviceId: "a"))
    #expect(!authority.isUnlockAllowed(deviceId: "nobody"))
}

// MARK: - 가까운 연결, 찍어 보기 막기, 판단 순서

@Test(arguments: ["100.64.0.1", "100.127.255.254", "fd7a:115c:a1e0::1"])
func tailscaleIsRemote(_ address: String) throws {
    #expect(!UnlockPolicy.isNearby(try #require(NWEndpoint.Host(address))))
}

@Test(arguments: ["100.63.255.255", "100.128.0.1", "192.168.0.10", "10.0.0.5", "fe80::1%awdl0", "fe80::1%en0"])
func localIsNearby(_ address: String) throws {
    #expect(UnlockPolicy.isNearby(try #require(NWEndpoint.Host(address))))
}

@Test func mappedTailscaleIsRemote() throws {
    #expect(!UnlockPolicy.isNearby(try #require(NWEndpoint.Host("::ffff:100.64.0.1"))))
}

@Test func unknownHostIsNotNearby() {
    #expect(!UnlockPolicy.isNearby(.name("dongiks-macbook-pro", nil)))
}

@Test func checkOrder() {
    #expect(UnlockPolicy.check(allowed: false, nearby: false, limiterAllows: false, locked: false) == .notAllowed)
    #expect(UnlockPolicy.check(allowed: true, nearby: false, limiterAllows: false, locked: false) == .notNearby)
    #expect(UnlockPolicy.check(allowed: true, nearby: true, limiterAllows: false, locked: false) == .tooManyTries)
    #expect(UnlockPolicy.check(allowed: true, nearby: true, limiterAllows: true, locked: false) == .notLocked)
    #expect(UnlockPolicy.check(allowed: true, nearby: true, limiterAllows: true, locked: true) == nil)
}

@Test func threeFailuresBlockForFiveMinutes() {
    var limiter = UnlockLimiter()
    let start = Date(timeIntervalSince1970: 0)
    for i in 0..<3 { limiter.recordFailure(now: start.addingTimeInterval(Double(i) * 10)) }
    #expect(!limiter.allows(now: start.addingTimeInterval(20 + 299)))
    #expect(limiter.allows(now: start.addingTimeInterval(20 + 301)))
}

@Test func failuresOutsideWindowDoNotCount() {
    var limiter = UnlockLimiter()
    let start = Date(timeIntervalSince1970: 0)
    limiter.recordFailure(now: start)
    limiter.recordFailure(now: start.addingTimeInterval(10))
    limiter.recordFailure(now: start.addingTimeInterval(400))
    #expect(limiter.allows(now: start.addingTimeInterval(401)))
}

@Test func successClearsFailures() {
    var limiter = UnlockLimiter()
    let start = Date(timeIntervalSince1970: 0)
    limiter.recordFailure(now: start)
    limiter.recordFailure(now: start)
    limiter.recordSuccess()
    limiter.recordFailure(now: start)
    #expect(limiter.allows(now: start))
}

// MARK: - 잠겨 있는 동안 받을 메시지

/// 잠긴 맥 뒤에서 앱이 열리거나 명령이 돌거나, 잠금 화면 칸에 글자가 들어가지 않게 막는다
@Test func lockedMacRefusesActions() {
    let refused: [ClientMessage] = [
        .press(page: 0, index: 0), .typeKey(.digit(1)), .typeText(text: "a"), .pressKey(.enter),
        .pointer(PointerEvent(kind: .click, x: 0.5, y: 0.5)), .setButton(page: 0, index: 0, button: DeckButton(label: "a", action: .terminal(directory: nil))),
        .clearButton(page: 0, index: 0), .setVolume(10), .volumeKey(.up), .listFolder(path: "~"),
        .moveButton(fromPage: 0, fromIndex: 0, toPage: 0, toIndex: 1, button: DeckButton(label: "a", action: .terminal(directory: nil))),
    ]
    for message in refused { #expect(!LockGate.allowsWhileLocked(message), "\(message)") }
}

@Test func lockedMacStillAcceptsUnlockAndReads() {
    let allowed: [ClientMessage] = [.unlock(password: "x"), .getApps, .stopScreen, .requestKeyframe]
    for message in allowed { #expect(LockGate.allowsWhileLocked(message), "\(message)") }
}

// MARK: - 맥 잠그기

@Test func lockMacMessageRoundTrips() throws {
    #expect(try ClientMessage.decode(ClientMessage.lockMac.encoded()) == .lockMac)
    #expect(try ClientMessage.lockMac.encoded() == #"{"type":"lockMac"}"#)
}

@Test func lockMacNeedsProtocolSix() {
    #expect(DeckProtocol.lockMac == 6)
}

@Test func moveButtonNeedsProtocolSeven() {
    #expect(DeckProtocol.moveButton == 7)
    #expect(DeckProtocol.current == DeckProtocol.moveButton)
}

/// 이미 잠긴 맥에는 잠그기를 받을 까닭이 없다(버튼도 숨는다)
@Test func lockedMacIgnoresLockMac() {
    #expect(!LockGate.allowsWhileLocked(.lockMac))
}
