import Network

/// 맥과 지금 어떤 길로 붙어 있는지. 상태 줄에 보여준다.
public enum ConnectionRoute: Equatable, Sendable {
    /// 같은 공유기(와이파이)를 거쳐서
    case sameWiFi
    /// 공유기 없이 기기끼리 직접 (에어드롭이 쓰는 awdl/llw 장치)
    case direct
    case wired
    case other

    public init(interfaceName: String?, isWiFi: Bool, isWired: Bool) {
        if let name = interfaceName, name.hasPrefix("awdl") || name.hasPrefix("llw") {
            self = .direct
        } else if isWiFi {
            self = .sameWiFi
        } else if isWired {
            self = .wired
        } else {
            self = .other
        }
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
        case .other: "기타 연결"
        }
    }

    public var symbol: String {
        switch self {
        case .sameWiFi: "wifi"
        case .direct: "antenna.radiowaves.left.and.right"
        case .wired: "cable.connector"
        case .other: "network"
        }
    }
}
