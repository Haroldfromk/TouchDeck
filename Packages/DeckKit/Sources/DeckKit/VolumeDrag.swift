/// 볼륨 띠를 끈 거리를 볼륨 키 누름으로 바꾼다.
/// 키 신호는 "한 칸 올려/내려"만 할 수 있어서, 값 대신 끈 거리로 몇 칸인지만 센다.
public struct VolumeDrag: Sendable {
    /// 몇 pt를 움직이면 한 칸인지
    public let step: Double
    private var sentSteps = 0

    public init(step: Double) {
        self.step = step
    }

    /// 손가락이 처음 닿은 곳에서 얼마나 움직였는지(올림 쪽이 +). 새로 넘은 칸만큼 키를 돌려준다.
    public mutating func update(distance: Double) -> [VolumeKey] {
        let steps = Int(distance / step)
        let diff = steps - sentSteps
        sentSteps = steps
        return Array(repeating: diff > 0 ? .up : .down, count: abs(diff))
    }

    /// 손을 떼면 다음 끌기는 처음부터 다시 센다
    public mutating func end() {
        sentSteps = 0
    }
}
