import Foundation
import Testing
@testable import DeckKit

private struct Missing: Error {}
private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw Missing() }
    return value
}

/// 아이패드 쪽 계산을 흉내 낸다: 맥이 준 공개 키와 사람이 친 숫자로 증명을 만든다.
private func answer(_ offer: PairingOffer, code: String) throws -> (publicKey: Data, derived: PairingCrypto.Derived) {
    let key = PairingCrypto.newPrivateKey()
    let mine = key.publicKey.rawRepresentation
    let derived = try PairingCrypto.derive(privateKey: key, peerPublicKey: offer.publicKey, code: code,
                                           macPublicKey: offer.publicKey, clientPublicKey: mine)
    return (mine, derived)
}

private func submit(_ a: inout PairingAuthority, _ offer: PairingOffer, code: String, deviceId: String = "d") throws -> PairingOutcome {
    let (pub, derived) = try answer(offer, code: code)
    return a.submit(clientPublicKey: pub, proof: derived.clientProof, deviceId: deviceId)
}

@Test func correctCodePairsWithSameTokenOnBothSides() throws {
    var a = PairingAuthority(trusted: [], random: { 4821 })
    let offer = try unwrap(a.beginPairing(deviceId: "ipad", deviceName: "iPad"))
    #expect(offer.code == "4821")
    #expect(a.currentCode == "4821")
    let (pub, derived) = try answer(offer, code: "4821")
    guard case .paired(let token, let macProof) = a.submit(clientPublicKey: pub, proof: derived.clientProof, deviceId: "ipad") else {
        Issue.record("not paired"); return
    }
    #expect(token == derived.token)
    #expect(macProof == derived.macProof)
    #expect(a.trusted.map(\.id) == ["ipad"])
    #expect(a.currentCode == nil)
}

@Test func codeKeepsLeadingZeros() {
    var a = PairingAuthority(trusted: [], random: { 42 })
    #expect(a.beginPairing(deviceId: "d", deviceName: "d")?.code == "0042")
}

@Test func wrongCodeIsWrong() throws {
    var a = PairingAuthority(trusted: [], random: { 4821 })
    let offer = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    #expect(try submit(&a, offer, code: "4812") == .wrong(remaining: 4))
}

@Test func garbagePublicKeyCountsAsWrong() throws {
    var a = PairingAuthority(trusted: [], random: { 4821 })
    _ = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    #expect(a.submit(clientPublicKey: Data([1, 2, 3]), proof: "00", deviceId: "d") == .wrong(remaining: 4))
}

@Test func fiveWrongCodesLockPairing() throws {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    let offer = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    for r in stride(from: 4, through: 1, by: -1) {
        #expect(try submit(&a, offer, code: "9999") == .wrong(remaining: r))
    }
    #expect(try submit(&a, offer, code: "9999") == .locked)
    #expect(a.isLocked)
    #expect(a.currentCode == nil)
    #expect(try submit(&a, offer, code: "1111") == .locked)
    #expect(a.beginPairing(deviceId: "d", deviceName: "d") == nil)
}

@Test func helloAgainDoesNotResetAttempts() throws {
    // 인사를 다시 할 때마다 횟수가 초기화되면 숫자를 무한히 찍어 볼 수 있다
    var a = PairingAuthority(trusted: [], random: { 1111 })
    var offer = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    _ = try submit(&a, offer, code: "0000")
    _ = try submit(&a, offer, code: "0001")
    offer = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    #expect(try submit(&a, offer, code: "0002") == .wrong(remaining: 2))
}

@Test func unlockAllowsPairingAgain() throws {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    let offer = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    for _ in 0..<5 { _ = try submit(&a, offer, code: "9999") }
    a.unlock()
    #expect(a.isLocked == false)
    let again = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    guard case .paired = try submit(&a, again, code: "1111") else { Issue.record("not paired"); return }
}

@Test func successResetsAttempts() throws {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    let first = try unwrap(a.beginPairing(deviceId: "a", deviceName: "a"))
    _ = try submit(&a, first, code: "0000", deviceId: "a")
    _ = try submit(&a, first, code: "1111", deviceId: "a")
    let second = try unwrap(a.beginPairing(deviceId: "b", deviceName: "b"))
    #expect(try submit(&a, second, code: "0000", deviceId: "b") == .wrong(remaining: 4))
}

@Test func codeFromOtherDeviceIsRejected() throws {
    var a = PairingAuthority(trusted: [], random: { 1234 })
    let offer = try unwrap(a.beginPairing(deviceId: "ipad", deviceName: "iPad"))
    #expect(try submit(&a, offer, code: "1234", deviceId: "intruder") == .notPending)
    // 맞춰 보지도 않았으니 횟수는 그대로
    #expect(try submit(&a, offer, code: "0000", deviceId: "ipad") == .wrong(remaining: 4))
}

@Test func newOfferUsesNewKey() throws {
    // 숫자를 다시 받을 때마다 맥의 임시 키도 새로 만든다
    var a = PairingAuthority(trusted: [], random: { 1111 })
    let one = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    let two = try unwrap(a.beginPairing(deviceId: "d", deviceName: "d"))
    #expect(one.publicKey != two.publicKey)
}

@Test func sessionKeysOnlyForTrustedDevice() throws {
    let token = Data(repeating: 3, count: 32)
    var a = PairingAuthority(trusted: [TrustedDevice(id: "d", name: "d", token: token.base64EncodedString())])
    let keys = try #require(a.sessionKeys(deviceId: "d", clientNonce: "c", macNonce: "m"))
    #expect(keys.clientProof == SessionKeys(token: token, clientNonce: "c", macNonce: "m").clientProof)
    #expect(a.sessionKeys(deviceId: "other", clientNonce: "c", macNonce: "m") == nil)
    a.revoke(deviceId: "d")
    #expect(a.sessionKeys(deviceId: "d", clientNonce: "c", macNonce: "m") == nil)
    #expect(a.trusted.isEmpty)
}
