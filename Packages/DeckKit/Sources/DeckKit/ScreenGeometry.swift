import CoreGraphics

/// 맥 화면 보기의 좌표 계산. 기기 쪽(터치 → 영상 안 위치)과 맥 쪽(영상 안 위치 → 맥 전체 좌표)이 같은 약속을 쓴다.
/// 영상 안 위치는 0~1(왼쪽 위가 0,0)이라 영상 크기나 레티나 배율과 상관없다.
public enum ScreenGeometry {
    /// 영상이 화면 안에 비율을 지키며 들어간 자리. 남는 쪽은 빈 띠(레터박스)가 된다.
    public static func videoRect(video: CGSize, in view: CGSize) -> CGRect {
        guard video.width > 0, video.height > 0 else { return .zero }
        let scale = min(view.width / video.width, view.height / video.height)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        return CGRect(x: (view.width - size.width) / 2, y: (view.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// 터치 위치 → 영상 안 0~1. 확대는 화면 가운데 기준으로 zoom배, 그다음 offset만큼 옮긴 상태.
    /// 빈 띠를 누르면 nil (맥에 아무것도 보내지 않는다).
    public static func normalized(touch: CGPoint, view: CGSize, video: CGSize,
                                  zoom: CGFloat = 1, offset: CGSize = .zero) -> CGPoint? {
        let rect = videoRect(video: video, in: view)
        guard rect.width > 0, rect.height > 0, zoom > 0 else { return nil }
        // 확대와 이동을 되돌려서 확대 전 화면 위치를 구한다
        let center = CGPoint(x: view.width / 2, y: view.height / 2)
        let x = center.x + (touch.x - offset.width - center.x) / zoom
        let y = center.y + (touch.y - offset.height - center.y) / zoom
        guard x >= rect.minX, x <= rect.maxX, y >= rect.minY, y <= rect.maxY else { return nil }
        return CGPoint(x: (x - rect.minX) / rect.width, y: (y - rect.minY) / rect.height)
    }

    /// 확대한 영상이 화면 밖으로 밀려나 빈 곳이 보이지 않게 옮길 수 있는 만큼만.
    /// covered: 화면 아래를 덮은 높이(입력칸과 키보드). 그만큼은 1배에서도 위로 밀어 올려 가려진 아래쪽을 볼 수 있다
    public static func clampOffset(_ offset: CGSize, zoom: CGFloat, view: CGSize, covered: CGFloat = 0) -> CGSize {
        let maxX = max(0, view.width * (zoom - 1) / 2)
        let maxY = max(0, view.height * (zoom - 1) / 2)
        let minY = -maxY - max(0, covered)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, minY), maxY))
    }

    /// 영상 안 0~1 → 맥 전체 좌표(포인트). display는 CGDisplayBounds 값이라 왼쪽/위 모니터는 음수에서 시작한다.
    /// 끝(1.0)은 옆 모니터 첫 칸이 되지 않게 마지막 칸에 둔다.
    public static func global(normalized p: CGPoint, display: CGRect) -> CGPoint {
        let nx = min(max(p.x, 0), 1), ny = min(max(p.y, 0), 1)
        return CGPoint(x: min(display.minX + nx * display.width, display.maxX - 1),
                       y: min(display.minY + ny * display.height, display.maxY - 1))
    }

    public static let minSide = 320
    public static let maxSide = 3840

    /// 보낼 영상 크기. 긴 변을 maxSide(320~3840) 안으로 비율 유지 축소, 키우지는 않는다. 압축기가 좋아하는 짝수로.
    public static func fit(width: Int, height: Int, maxSide requested: Int) -> (width: Int, height: Int) {
        let limit = Double(min(max(requested, minSide), maxSide))
        let scale = min(1, limit / Double(max(width, height, 1)))
        func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }
}

/// 두 손가락이 닿았을 때 무엇을 할지. 한 번 정하면 손을 뗄 때까지 바꾸지 않는다.
/// 손가락 간격이 8% 넘게 변하면 확대, 그 전에 12pt 넘게 움직이면 쓸기다.
/// 쓸기는 확대 중이면 보는 위치 옮기기, 원래 크기면 맥 스크롤(맥 스크롤은 확대 중에도 한 손가락으로 된다).
public enum TwoFinger: Equatable, Sendable {
    case undecided, zoom, pan, scroll

    public static let zoomScale: CGFloat = 0.08
    public static let moveDistance: CGFloat = 12

    /// scale: 핀치 배율(1이 그대로), moved: 닿은 뒤 움직인 거리(pt), zoom: 지금 확대 배율,
    /// covered: 키보드와 입력칸이 덮은 높이. 덮여 있으면 1배여도 쓸기는 보는 위치 옮기기다
    public static func decide(_ current: TwoFinger, scale: CGFloat, moved: CGFloat, zoom: CGFloat, covered: CGFloat = 0) -> TwoFinger {
        guard current == .undecided else { return current }
        if abs(scale - 1) > zoomScale { return .zoom }
        if moved > moveDistance { return zoom > 1.01 || covered > 0 ? .pan : .scroll }
        return .undecided
    }
}
