import CryptoKit
import Foundation

/// HMAC-SHA256 결과를 소문자 16진수 글자로. ESP32(mbedtls)에서도 같은 값을 만들 수 있다.
public func hmacHex(key: SymmetricKey, _ message: String) -> String {
    HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key).map { String(format: "%02x", $0) }.joined()
}

/// 처음 페어링할 때의 키 교환. 맥과 기기가 각자 임시 키를 만들고 공개 키만 주고받는다(X25519).
/// 둘이 계산한 공유 비밀에 4자리 숫자를 섞어서 토큰을 만든다. 토큰도 숫자도 네트워크로 나가지 않는다.
public enum PairingCrypto {
    public struct Derived: Sendable {
        /// 앞으로 이 기기임을 증명할 비밀 값 (32바이트)
        public let token: Data
        /// 기기가 "같은 숫자를 안다"는 증명
        public let clientProof: String
        /// 맥이 "같은 숫자를 안다"는 증명
        public let macProof: String
    }

    public static func newPrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    public static func derive(privateKey: Curve25519.KeyAgreement.PrivateKey, peerPublicKey: Data, code: String,
                              macPublicKey: Data, clientPublicKey: Data) throws -> Derived {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        // 두 공개 키를 같이 넣어서, 다른 키 쌍으로 만든 결과와 섞일 수 없게 한다
        let transcript = macPublicKey + clientPublicKey
        let salt = Data(code.utf8)
        let confirmKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                                        sharedInfo: Data("touchdeck confirm".utf8) + transcript, outputByteCount: 32)
        let token = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                                   sharedInfo: Data("touchdeck token".utf8) + transcript, outputByteCount: 32)
        return Derived(token: token.withUnsafeBytes { Data($0) },
                       clientProof: hmacHex(key: confirmKey, "client"),
                       macProof: hmacHex(key: confirmKey, "mac"))
    }
}

/// 다시 붙을 때. 양쪽이 낸 무작위 값(nonce) 두 개와 토큰으로 이번 접속 전용 키와 증명을 만든다.
public struct SessionKeys: Sendable {
    /// 맥이 "토큰을 안다"는 증명. 기기가 먼저 확인해서 가짜 맥을 걸러 낸다.
    public let macProof: String
    /// 기기가 "토큰을 안다"는 증명
    public let clientProof: String
    let clientToMac: SymmetricKey
    let macToClient: SymmetricKey

    public init(token: Data, clientNonce: String, macNonce: String) {
        let key = SymmetricKey(data: token)
        let nonces = "\(clientNonce)|\(macNonce)"
        macProof = hmacHex(key: key, "mac|\(nonces)")
        clientProof = hmacHex(key: key, "client|\(nonces)")
        let salt = Data(nonces.utf8)
        clientToMac = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: salt, info: Data("touchdeck c2m".utf8), outputByteCount: 32)
        macToClient = HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: salt, info: Data("touchdeck m2c".utf8), outputByteCount: 32)
    }

    public static func makeNonce() -> String {
        var rng = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &rng)) }.joined()
    }
}

/// 허락받은 뒤의 모든 메시지를 감싸는 봉투. 메시지 하나하나를 이번 접속 전용 키로 암호화한다(ChaChaPoly).
/// 내용이 보이지 않고(키패드로 친 비밀번호 숫자 포함), 토큰을 모르면 봉투를 새로 만들거나 바꿀 수 없다.
/// 번호도 암호화에 묶어서, 번호가 늘어나야만 받으니 같은 메시지를 다시 보내도 걸린다.
public struct SecureChannel: Sendable {
    public enum Role: Sendable { case client, mac }
    public enum OpenError: Error, Equatable { case notSecure, badSignature, replayed }

    private struct Envelope: Codable {
        var type = "secure"
        var seq: UInt64
        /// ChaChaPoly 결과(nonce 12바이트 + 암호문 + 확인용 태그 16바이트)를 base64로
        var box: String
    }

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sentSeq: UInt64 = 0
    private var receivedSeq: UInt64 = 0

    public init(keys: SessionKeys, role: Role) {
        switch role {
        case .client: sendKey = keys.clientToMac; receiveKey = keys.macToClient
        case .mac: sendKey = keys.macToClient; receiveKey = keys.clientToMac
        }
    }

    public mutating func seal(_ body: String) -> String {
        sentSeq += 1
        let sealed = try? ChaChaPoly.seal(Data(body.utf8), using: sendKey, authenticating: Data("\(sentSeq)".utf8))
        let envelope = Envelope(seq: sentSeq, box: sealed?.combined.base64EncodedString() ?? "")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(envelope)) ?? Data(), as: UTF8.self)
    }

    public mutating func open(_ text: String) throws -> String {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)), envelope.type == "secure" else {
            throw OpenError.notSecure
        }
        guard let combined = Data(base64Encoded: envelope.box),
              let box = try? ChaChaPoly.SealedBox(combined: combined),
              let plain = try? ChaChaPoly.open(box, using: receiveKey, authenticating: Data("\(envelope.seq)".utf8)),
              let body = String(data: plain, encoding: .utf8) else {
            throw OpenError.badSignature
        }
        guard envelope.seq > receivedSeq else { throw OpenError.replayed }
        receivedSeq = envelope.seq
        return body
    }
}
