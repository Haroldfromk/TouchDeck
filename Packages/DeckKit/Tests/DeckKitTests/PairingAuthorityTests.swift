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

@Test func fiveWrongCodesRegenerate() {
    var a = PairingAuthority(trusted: [], random: { 1111 })
    _ = a.beginPairing(deviceId: "d", deviceName: "d")
    for r in stride(from: 4, through: 1, by: -1) {
        #expect(a.submit(code: "9999", deviceId: "d") == .wrong(remaining: r))
    }
    guard case .regenerated = a.submit(code: "9999", deviceId: "d") else { Issue.record("not regenerated"); return }
    #expect(a.submit(code: "9999", deviceId: "d") == .wrong(remaining: 4))
}

@Test func codeFromOtherDeviceIsRejected() {
    var a = PairingAuthority(trusted: [], random: { 1234 })
    _ = a.beginPairing(deviceId: "ipad", deviceName: "iPad")
    #expect(a.submit(code: "1234", deviceId: "intruder") == .wrong(remaining: 4))
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
