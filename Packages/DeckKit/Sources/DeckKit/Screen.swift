import Foundation

/// 맥 모니터 하나. 크기는 포인트(레티나 배율 전), 미리보기는 긴 변 320px JPEG를 base64로.
public struct DisplayInfo: Codable, Equatable, Hashable, Sendable {
    public var id: UInt32
    public var name: String
    public var width: Int
    public var height: Int
    public var thumbnail: String

    public init(id: UInt32, name: String, width: Int, height: Int, thumbnail: String) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.thumbnail = thumbnail
    }
}

/// 화면 위의 터치 하나를 맥 마우스로. x, y는 영상 안 0~1 위치(왼쪽 위가 0,0). dx, dy는 스크롤 양(포인트).
public struct PointerEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 한 손가락 끌기: 누름 → 움직임 → 뗌
        case down, move, up
        case click, rightClick, scroll
    }

    public var kind: Kind
    public var x: Double
    public var y: Double
    public var dx: Double
    public var dy: Double

    public init(kind: Kind, x: Double, y: Double, dx: Double = 0, dy: Double = 0) {
        self.kind = kind
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
    }
}

/// 화면 보기 프레임 수. 30과 60만 쓴다
public enum ScreenFPS {
    public static let low = 30
    public static let high = 60

    /// 30, 60이 아닌 값은 가까운 쪽으로 (45부터 60)
    public static func normalize(_ value: Int) -> Int {
        value < 45 ? low : high
    }
}

/// 화면 보기 요청에 대한 맥의 답
public enum ScreenState: String, Codable, Sendable {
    case ok
    /// 맥 메뉴에서 이 기기의 "화면 보기 허용"이 꺼져 있다
    case notAllowed
    /// 맥 앱에 화면 기록 권한이 없다
    case noPermission
    /// 다른 기기가 보고 있다
    case busy
    /// 맥이 잠겨 있다(화면 보호기 포함)
    case locked
    /// 맥에서 끊었다
    case stopped
    /// 화면은 보이지만 맥 앱에 손쉬운 사용 권한이 없어서 조작은 안 된다
    case noInput
}

/// 화면을 보여줘도 되는지. 네트워크와 캡처는 모르고 판단만 한다.
public enum ScreenAccess {
    /// viewer: 지금 보고 있는 기기 ID. 같은 기기가 다시 붙으면 이어서 볼 수 있다.
    public static func decide(allowed: Bool, permission: Bool, locked: Bool, viewer: String?, requester: String) -> ScreenState {
        // 허용 안 된 기기에는 권한이나 잠김 상태도 알려 주지 않는다
        guard allowed else { return .notAllowed }
        guard permission else { return .noPermission }
        guard !locked else { return .locked }
        if let viewer, viewer != requester { return .busy }
        return .ok
    }
}
