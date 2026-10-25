import Foundation
import Network

/// 맥 잠금 풀기를 받아도 되는지. 가까이 있을 때만(같은 와이파이, 기기끼리 직접 연결), 허용한 기기만, 찍어 보기는 막는다
public enum UnlockPolicy {
    /// 연결 상대 주소가 Tailscale이 아닌지. Tailscale은 IPv4 100.64.0.0/10, IPv6 fd7a:115c:a1e0::/48을 쓴다.
    /// 이름으로 된 주소처럼 판단할 수 없는 건 가깝지 않은 것으로 본다
    public static func isNearby(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4, .ipv6: !isTailscale(host)
        default: false
        }
    }

    /// 주소가 Tailscale 범위인지. 이름으로 된 주소는 알 수 없으니 false
    public static func isTailscale(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let address):
            return isTailscale(ipv4: [UInt8](address.rawValue))
        case .ipv6(let address):
            let bytes = [UInt8](address.rawValue)
            // IPv4를 IPv6 모양으로 보여 주는 경우(::ffff:a.b.c.d)
            if bytes.count == 16, bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
                return isTailscale(ipv4: Array(bytes[12..<16]))
            }
            return bytes.count == 16 && bytes[0..<6].elementsEqual([0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0])
        default:
            return false
        }
    }

    private static func isTailscale(ipv4 bytes: [UInt8]) -> Bool {
        bytes.count == 4 && bytes[0] == 100 && bytes[1] & 0xC0 == 64
    }

    /// 이 순서로 본다. nil이면 쳐도 된다
    public static func check(allowed: Bool, nearby: Bool, limiterAllows: Bool, locked: Bool) -> UnlockResult? {
        if !allowed { return .notAllowed }
        if !nearby { return .notNearby }
        if !limiterAllows { return .tooManyTries }
        if !locked { return .notLocked }
        return nil
    }
}

/// 찍어 보기 막기: 300초 안에 3번 틀리면 그때부터 300초 동안 받지 않는다. 성공하면 처음부터
public struct UnlockLimiter: Sendable {
    public static let maxFailures = 3
    public static let window: TimeInterval = 300

    private var failures: [Date] = []
    private var blockedUntil = Date.distantPast

    public init() {}

    public func allows(now: Date) -> Bool {
        now >= blockedUntil
    }

    public mutating func recordFailure(now: Date) {
        failures = failures.filter { now.timeIntervalSince($0) < Self.window } + [now]
        if failures.count >= Self.maxFailures {
            blockedUntil = now.addingTimeInterval(Self.window)
            failures = []
        }
    }

    public mutating func recordSuccess() {
        failures = []
        blockedUntil = .distantPast
    }
}

/// 맥이 잠겨 있는 동안 받을 메시지. 잠긴 맥 뒤에서 앱이 열리거나 명령이 돌거나,
/// 잠금 화면 칸에 글자가 들어가지 않게 맥에 무언가를 하는 메시지는 막는다.
/// default를 두지 않아서, 새 메시지를 더하면 여기서 정해야 컴파일된다
public enum LockGate {
    public static func allowsWhileLocked(_ message: ClientMessage) -> Bool {
        switch message {
        case .press, .typeKey, .typeText, .pressKey, .pointer, .setButton, .clearButton,
             .setVolume, .volumeKey, .listFolder, .startScreen, .screenOptions, .lockMac:
            false
        case .unlock, .getApps, .listDisplays, .stopScreen, .requestKeyframe, .hello, .pair, .auth:
            true
        }
    }
}
