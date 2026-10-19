import Testing
@testable import DeckKit

@Test func correctCodePairsAndTrusts() {
    var a = PairingAuthority(trusted: [], random: { 4821 })
    let code = a.beginPairing(deviceId: "ipad", deviceName: "iPad")
    #expect(code == "4821")
    #expect(a.currentCode == "4821")
    guard case .paired(let token) = a.submit(code: "4821", deviceId: "ipad") else { Issue.record("not paired"); return }
    #expect(a.trusted.map(\.id) == ["ipad"])
    #expect(a.verify(deviceId: "ipad", nonce: "n1", signature: pairingSignature(token: token, nonce: "n1")))
    #expect(a.currentCode == nil)
}

@Test func codeKeepsLeadingZeros() {
    var a = PairingAuthority(trusted: [], random: { 42 })
    #expect(a.beginPairing(deviceId: "d", deviceName: "d") == "0042")
}

@Test func fiveWrongCodesLockPairing() {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    _ = a.beginPairing(deviceId: "d", deviceName: "d")
    for r in stride(from: 4, through: 1, by: -1) {
        #expect(a.submit(code: "9999", deviceId: "d") == .wrong(remaining: r))
    }
    #expect(a.submit(code: "9999", deviceId: "d") == .locked)
    #expect(a.isLocked)
    #expect(a.currentCode == nil)
    #expect(a.submit(code: "1111", deviceId: "d") == .locked)
    #expect(a.beginPairing(deviceId: "d", deviceName: "d") == nil)
}

@Test func helloAgainDoesNotResetAttempts() {
    // 인사를 다시 할 때마다 횟수가 초기화되면 숫자를 무한히 찍어 볼 수 있다
    var a = PairingAuthority(trusted: [], random: { 1111 })
    _ = a.beginPairing(deviceId: "d", deviceName: "d")
    _ = a.submit(code: "0000", deviceId: "d")
    _ = a.submit(code: "0001", deviceId: "d")
    _ = a.beginPairing(deviceId: "d", deviceName: "d")
    #expect(a.submit(code: "0002", deviceId: "d") == .wrong(remaining: 2))
}

@Test func unlockAllowsPairingAgain() {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    _ = a.beginPairing(deviceId: "d", deviceName: "d")
    for _ in 0..<5 { _ = a.submit(code: "9999", deviceId: "d") }
    a.unlock()
    #expect(a.isLocked == false)
    #expect(a.beginPairing(deviceId: "d", deviceName: "d") == "1111")
    guard case .paired = a.submit(code: "1111", deviceId: "d") else { Issue.record("not paired"); return }
}

@Test func successResetsAttempts() {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    _ = a.beginPairing(deviceId: "a", deviceName: "a")
    _ = a.submit(code: "0000", deviceId: "a")
    _ = a.submit(code: "1111", deviceId: "a")
    _ = a.beginPairing(deviceId: "b", deviceName: "b")
    #expect(a.submit(code: "0000", deviceId: "b") == .wrong(remaining: 4))
}

@Test func revokedDeviceFailsVerify() {
    var a = PairingAuthority(trusted: [TrustedDevice(id: "d", name: "d", token: "t")])
    a.revoke(deviceId: "d")
    #expect(!a.verify(deviceId: "d", nonce: "n", signature: pairingSignature(token: "t", nonce: "n")))
    #expect(a.trusted.isEmpty)
}

@Test func wrongSignatureFails() {
    let a = PairingAuthority(trusted: [TrustedDevice(id: "d", name: "d", token: "t")])
    #expect(!a.verify(deviceId: "d", nonce: "n", signature: pairingSignature(token: "other", nonce: "n")))
}

@Test func signatureIsLowercaseHexSHA256() {
    // HMAC-SHA256(key: "key", data: "The quick brown fox jumps over the lazy dog") 공개 테스트 값
    #expect(pairingSignature(token: "key", nonce: "The quick brown fox jumps over the lazy dog")
            == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
}
