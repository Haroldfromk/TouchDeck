/// 허락받기 전 접속은 누가 보냈는지 모른다. 같은 와이파이의 누구라도 맥 앱을 귀찮게 못 하게 상한을 둔다.
enum PreAuthLimits {
    static let maxPending = 8
    static let maxMessageBytes = 8 * 1024
    static let maxNameLength = 32

    /// 새 접속 하나를 받을 자리를 만들려면 끊어야 할 오래된 접속들.
    /// 새 접속을 거절하지 않고 옛것을 끊는 건, 반쯤 죽은 접속이 자리를 차지해도 해롤드 기기가 다시 붙게 하려고.
    static func toDrop<T>(pending: [T]) -> [T] {
        Array(pending.prefix(max(0, pending.count - maxPending + 1)))
    }

    /// hello, pair, auth는 1KB도 안 된다.
    static func allows(_ text: String) -> Bool {
        text.utf8.count <= maxMessageBytes
    }

    /// 기기 이름은 상대가 정한다. 메뉴바 창이 길게 늘어나지 않게 자른다.
    static func displayName(_ name: String) -> String {
        name.count <= maxNameLength ? name : name.prefix(maxNameLength) + "…"
    }
}
