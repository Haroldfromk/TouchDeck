import Darwin
import Foundation

/// 맥의 네트워크 장치에 붙은 주소 보기
enum NetworkLinks {
    /// 그 장치에 집 네트워크 주소(192.168…, 공유기가 준 IPv6) 없이 근처 전용 주소(169.254.x.x, fe80::)만 있는지.
    /// 아이폰을 케이블로 꽂으면 생기는 장치가 이렇다. 장치를 찾지 못하면 false
    static func hasOnlyLocalAddresses(_ name: String) -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        var found = false
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: entry.pointee.ifa_name) == name, let addr = entry.pointee.ifa_addr else { continue }
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                found = true
                let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                // 169.254.0.0/16이 아니면 집 네트워크 주소다
                if ip >> 16 != 0xA9FE { return false }
            case AF_INET6:
                found = true
                let bytes = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr.__u6_addr.__u6_addr8 }
                // fe80::/10이 아니면 공유기가 준 주소다
                if !(bytes.0 == 0xfe && bytes.1 & 0xc0 == 0x80) { return false }
            default:
                continue
            }
        }
        return found
    }
}
