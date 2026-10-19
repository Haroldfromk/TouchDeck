/// 소리 묶음을 짧게 쌓아 두고 튼다. 와이파이 도착 간격이 들쭉날쭉해도 끊기지 않게,
/// 그러면서도 쌓인 양이 계속 늘어 소리가 점점 늦어지지 않게.
/// 플레이어는 모르고 "몇 초 분량이 들어왔다/다 틀었다"만 센다.
public struct AudioJitter: Sendable {
    /// 처음과 끊긴 뒤에는 이만큼 쌓이면 틀기 시작한다
    public static let startAt = 0.06
    /// 이보다 많이 쌓이면 새 묶음을 버리기 시작한다
    public static let dropAbove = 0.2
    /// 버리다가 이 아래로 내려가면 다시 받는다
    public static let resumeBelow = 0.1
    /// 0.02를 여러 번 더하면 끝자리가 어긋난다(0.1999…98). 경계는 이만큼 여유를 두고 비교한다
    private static let epsilon = 1e-9

    public enum Decision: Equatable, Sendable {
        case drop, queue, queueAndStart
    }

    /// 플레이어에 넣었지만 아직 다 틀지 않은 양(초)
    public private(set) var queued = 0.0
    public private(set) var playing = false
    private var dropping = false

    public init() {}

    /// 묶음 하나가 도착했다. 버릴지, 넣을지, 넣고 틀기 시작할지
    public mutating func arrive(_ seconds: Double) -> Decision {
        if dropping {
            if queued > Self.resumeBelow - Self.epsilon { return .drop }
            dropping = false
        }
        if queued + seconds > Self.dropAbove + Self.epsilon {
            dropping = true
            return .drop
        }
        queued += seconds
        if !playing && queued >= Self.startAt - Self.epsilon {
            playing = true
            return .queueAndStart
        }
        return .queue
    }

    /// 넣었던 묶음 하나를 다 틀었다. 비었으면 true (플레이어를 멈추고 다시 쌓일 때까지 기다린다)
    public mutating func finished(_ seconds: Double) -> Bool {
        queued -= seconds
        guard queued <= Self.epsilon else { return false }
        queued = 0
        playing = false
        return true
    }
}
