import CryptoKit
import Foundation

public struct TrustedDevice: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// 키 교환으로 만든 32바이트 토큰(base64). 네트워크로 오간 적이 없는 값이다.
    public var token: String

    public init(id: String, name: String, token: String) {
        self.id = id
        self.name = name
        self.token = token
    }
}

/// 맥이 페어링을 시작하며 내놓는 것: 메뉴바에 보여줄 숫자, 기기에 보낼 임시 공개 키.
public struct PairingOffer: Equatable, Sendable {
    public let code: String
    public let publicKey: Data
}

public enum PairingOutcome: Equatable, Sendable {
    case paired(token: Data, macProof: String)
    case wrong(remaining: Int)
    /// 틀린 횟수를 다 써서 잠겼다. 해롤드가 맥 메뉴에서 풀어야 다시 페어링할 수 있다.
    case locked
    /// 지금 숫자를 받은 기기가 아니다. 맞춰 보지도 않으니 횟수를 쓰지 않는다.
    case notPending
}

/// 맥 쪽의 허락 판정. 네트워크와 저장은 모르고 판단만 한다.
public struct PairingAuthority: Sendable {
    public static let maxAttempts = 5

    public private(set) var trusted: [TrustedDevice]
    /// 지금 메뉴바에 보여줄 4자리 숫자. 페어링 중이 아니면 nil.
    public private(set) var currentCode: String?
    /// 틀린 횟수를 다 쓰면 잠긴다. 인사를 다시 해도 안 풀린다 (숫자 찍어 보기 막기).
    public private(set) var isLocked = false

    private var pending: (id: String, name: String, key: Curve25519.KeyAgreement.PrivateKey)?
    private var attemptsLeft = PairingAuthority.maxAttempts
    private let random: @Sendable () -> UInt32

    public init(trusted: [TrustedDevice], random: @escaping @Sendable () -> UInt32 = { .random(in: 0...UInt32.max) }) {
        self.trusted = trusted
        self.random = random
    }

    /// 새 숫자와 새 임시 키를 만든다. 잠겨 있으면 nil. 틀린 횟수는 기기가 바뀌거나 다시 인사해도 이어진다.
    public mutating func beginPairing(deviceId: String, deviceName: String) -> PairingOffer? {
        guard !isLocked else { return nil }
        let key = PairingCrypto.newPrivateKey()
        pending = (deviceId, deviceName, key)
        let code = String(format: "%04u", random() % 10_000)
        currentCode = code
        return PairingOffer(code: code, publicKey: key.publicKey.rawRepresentation)
    }

    /// 기기가 보낸 공개 키와 증명을 메뉴바 숫자로 확인한다. 숫자 자체는 오지 않는다.
    public mutating func submit(clientPublicKey: Data, proof: String, deviceId: String) -> PairingOutcome {
        guard !isLocked else { return .locked }
        guard let pending, pending.id == deviceId, let code = currentCode else { return .notPending }
        let macPublicKey = pending.key.publicKey.rawRepresentation
        if let derived = try? PairingCrypto.derive(privateKey: pending.key, peerPublicKey: clientPublicKey, code: code,
                                                   macPublicKey: macPublicKey, clientPublicKey: clientPublicKey),
           derived.clientProof == proof {
            trusted.removeAll { $0.id == deviceId }
            trusted.append(TrustedDevice(id: deviceId, name: pending.name, token: derived.token.base64EncodedString()))
            self.pending = nil
            currentCode = nil
            attemptsLeft = Self.maxAttempts
            return .paired(token: derived.token, macProof: derived.macProof)
        }
        attemptsLeft -= 1
        if attemptsLeft <= 0 {
            isLocked = true
            self.pending = nil
            currentCode = nil
            return .locked
        }
        return .wrong(remaining: attemptsLeft)
    }

    /// 맥 메뉴의 "새 기기 허락 다시 받기"
    public mutating func unlock() {
        isLocked = false
        attemptsLeft = Self.maxAttempts
    }

    /// 허락한 기기면 이번 접속의 키와 증명. 아니면 nil.
    public func sessionKeys(deviceId: String, clientNonce: String, macNonce: String) -> SessionKeys? {
        guard let device = trusted.first(where: { $0.id == deviceId }), let token = Data(base64Encoded: device.token) else { return nil }
        return SessionKeys(token: token, clientNonce: clientNonce, macNonce: macNonce)
    }

    public func isTrusted(deviceId: String) -> Bool {
        trusted.contains { $0.id == deviceId }
    }

    public mutating func revoke(deviceId: String) {
        trusted.removeAll { $0.id == deviceId }
    }

    /// 기기가 페어링 도중 연결을 끊으면 숫자를 지운다.
    public mutating func cancelPairing(deviceId: String) {
        guard pending?.id == deviceId else { return }
        pending = nil
        currentCode = nil
    }
}
