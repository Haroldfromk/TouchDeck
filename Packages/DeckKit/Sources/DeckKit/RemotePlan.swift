/// 맥을 찾는 다음 걸음
public enum ConnectStep: Equatable, Sendable {
    case keepSearching
    case useBonjour
    case useRemote(host: String)
}

/// 집에서는 지금처럼 Bonjour로, 못 찾으면 밖에서 붙을 주소(Tailscale)로
public enum RemotePlan {
    /// Bonjour로 이만큼 못 찾으면 원격 주소로 간다
    public static let wait = 3.0

    public static func next(bonjourFound: Bool, waited: Double, remoteHost: String?, localNetworkDenied: Bool) -> ConnectStep {
        // 집에서는 기다리지 않고 바로 Bonjour
        if bonjourFound { return .useBonjour }
        // 로컬 네트워크 권한이 막혀도 Tailscale 주소는 상관없다
        if let remoteHost, waited >= wait || localNetworkDenied { return .useRemote(host: remoteHost) }
        return .keepSearching
    }
}

/// 화면 보기를 시작할 때 맥에 달라고 할 값
public struct ScreenSettings: Equatable, Sendable {
    public var maxSide: Int
    public var fps: Int
    public var audio: Bool
    /// 초당 비트 상한. nil이면 맥이 정한 대로
    public var bitrateCap: Int?

    public init(maxSide: Int, fps: Int, audio: Bool, bitrateCap: Int?) {
        self.maxSide = maxSide
        self.fps = fps
        self.audio = audio
        self.bitrateCap = bitrateCap
    }
}

/// 원격(VPN)일 때는 LTE에서도 버티게 낮춘다. 집에서 고른 값은 건드리지 않는다
public enum ScreenQuality {
    public static let remoteMaxSide = 1600
    public static let remoteFPS = ScreenFPS.low
    public static let remoteBitrateCap = 4_000_000

    /// remoteOverride: 원격 중에 툴바에서 바꾼 값 (그 연결 동안만)
    public static func settings(route: ConnectionRoute?, deviceLongSide: Int, savedFPS: Int, savedAudio: Bool,
                                remoteOverride: (fps: Int, audio: Bool)?) -> ScreenSettings {
        guard route == .vpn else {
            return ScreenSettings(maxSide: deviceLongSide, fps: savedFPS, audio: savedAudio, bitrateCap: nil)
        }
        return ScreenSettings(maxSide: min(deviceLongSide, remoteMaxSide),
                              fps: remoteOverride?.fps ?? remoteFPS,
                              audio: remoteOverride?.audio ?? false,
                              bitrateCap: remoteBitrateCap)
    }
}
