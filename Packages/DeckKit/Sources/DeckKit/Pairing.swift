import CryptoKit
import Foundation

/// 페어링 뒤에는 토큰을 다시 보내지 않는다. 맥이 매번 새 nonce를 보내고,
/// 기기는 토큰으로 만든 서명만 돌려준다.
public func pairingSignature(token: String, nonce: String) -> String {
    let mac = HMAC<SHA256>.authenticationCode(for: Data(nonce.utf8), using: SymmetricKey(data: Data(token.utf8)))
    return mac.map { String(format: "%02x", $0) }.joined()
}

public struct TrustedDevice: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var token: String

    public init(id: String, name: String, token: String) {
        self.id = id
        self.name = name
        self.token = token
    }
}

public enum PairingOutcome: Equatable, Sendable {
    case paired(token: String)
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

    private var pendingDevice: (id: String, name: String)?
    private var attemptsLeft = PairingAuthority.maxAttempts
    private let random: @Sendable () -> UInt32

    public init(trusted: [TrustedDevice], random: @escaping @Sendable () -> UInt32 = { .random(in: 0...UInt32.max) }) {
        self.trusted = trusted
        self.random = random
    }

    /// 새 숫자를 만든다. 잠겨 있으면 nil. 틀린 횟수는 기기가 바뀌거나 다시 인사해도 이어진다.
    public mutating func beginPairing(deviceId: String, deviceName: String) -> String? {
        guard !isLocked else { return nil }
        pendingDevice = (deviceId, deviceName)
        let code = makeCode()
        currentCode = code
        return code
    }

    public mutating func submit(code: String, deviceId: String) -> PairingOutcome {
        guard !isLocked else { return .locked }
        guard let pending = pendingDevice, pending.id == deviceId else { return .notPending }
        if code == currentCode {
            let token = Self.makeToken()
            trusted.removeAll { $0.id == deviceId }
            trusted.append(TrustedDevice(id: deviceId, name: pending.name, token: token))
            pendingDevice = nil
            currentCode = nil
            attemptsLeft = Self.maxAttempts
            return .paired(token: token)
        }
        attemptsLeft -= 1
        if attemptsLeft <= 0 {
            isLocked = true
            pendingDevice = nil
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

    public func verify(deviceId: String, nonce: String, signature: String) -> Bool {
        guard let device = trusted.first(where: { $0.id == deviceId }) else { return false }
        return pairingSignature(token: device.token, nonce: nonce) == signature
    }

    public func isTrusted(deviceId: String) -> Bool {
        trusted.contains { $0.id == deviceId }
    }

    public mutating func revoke(deviceId: String) {
        trusted.removeAll { $0.id == deviceId }
    }

    /// 기기가 페어링 도중 연결을 끊으면 숫자를 지운다.
    public mutating func cancelPairing(deviceId: String) {
        guard pendingDevice?.id == deviceId else { return }
        pendingDevice = nil
        currentCode = nil
    }

    private func makeCode() -> String {
        String(format: "%04u", random() % 10_000)
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = rng.next() }
        return Data(bytes).base64EncodedString()
    }
}
