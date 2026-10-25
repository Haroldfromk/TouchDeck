import Network

/// 맥과 지금 어떤 길로 붙어 있는지. 상태 줄에 보여준다.
public enum ConnectionRoute: String, Codable, Equatable, Sendable {
    /// 같은 공유기(와이파이)를 거쳐서
    case sameWiFi
    /// 공유기 없이 기기끼리 직접 (에어드롭이 쓰는 awdl/llw 장치)
    case direct
    case wired
    /// Tailscale 같은 VPN으로 밖에서 (utun 장치)
    case vpn
    case other

    public init(interfaceName: String?, isWiFi: Bool, isWired: Bool) {
        if let name = interfaceName, name.hasPrefix("awdl") || name.hasPrefix("llw") {
            self = .direct
        } else if let name = interfaceName, name.hasPrefix("utun") {
            self = .vpn
        } else if isWiFi {
            self = .sameWiFi
        } else if isWired {
            self = .wired
        } else {
            self = .other
        }
    }

    /// 맥 쪽에서 판단할 때: 상대 주소가 Tailscale이면 장치와 상관없이 원격이다.
    /// 아이폰은 자기 쪽 장치를 엉뚱하게 알려 줄 때가 있어서(Tailscale은 pdp_ip0, 직접 연결은 기타) 맥이 정한 값을 이름표로 쓴다
    /// 맥 쪽에서 판단할 때. 맥은 자기가 확실히 아는 것만 정한다: 원격(Tailscale 주소), 직접 연결, 그 밖은 같은 네트워크.
    /// link는 상대 주소에 붙은 장치 이름(fe80::…%awdl0의 awdl0)이다. 연결이 "쓸 수 있는 장치 목록"은
    /// 실제로 쓰는 장치와 달라서(랜으로 온 연결도 awdl0이 첫째로 나왔다) 쓰지 않는다.
    /// 맥이 랜선으로 붙어 있어도 와이파이로 붙은 기기에게는 같은 네트워크라, 와이파이인지 유선인지는 기기가 정한다
    public init(macSideRemote remote: NWEndpoint.Host?, link: String?) {
        if let remote, UnlockPolicy.isTailscale(remote) {
            self = .vpn
        } else if let link, link.hasPrefix("awdl") || link.hasPrefix("llw") {
            self = .direct
        } else {
            self = .sameWiFi
        }
    }

    /// 기기가 보여 줄 길. 직접 연결과 원격은 맥 판단을, 같은 네트워크면 기기 자신의 유선 판단을 쓴다
    public static func shown(mac: ConnectionRoute?, local: ConnectionRoute?) -> ConnectionRoute? {
        guard let mac else { return local }
        if mac == .sameWiFi, local == .wired { return .wired }
        return mac
    }

    /// 연결이 실제로 타고 있는 네트워크 장치로 판단한다
    public init(path: NWPath) {
        let interface = path.availableInterfaces.first
        self.init(interfaceName: interface?.name,
                  isWiFi: interface?.type == .wifi,
                  isWired: interface?.type == .wiredEthernet)
    }

    public var label: String {
        switch self {
        case .sameWiFi: "같은 와이파이"
        case .direct: "직접 연결"
        case .wired: "유선"
        case .vpn: "원격(VPN)"
        case .other: "기타 연결"
        }
    }

    public var symbol: String {
        switch self {
        case .sameWiFi: "wifi"
        case .direct: "antenna.radiowaves.left.and.right"
        case .wired: "cable.connector"
        case .vpn: "lock.shield"
        case .other: "network"
        }
    }
}
