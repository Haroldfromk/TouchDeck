import CoreGraphics
import Testing
@testable import DeckKit

// MARK: - 영상이 화면에 들어가는 자리

@Test func wideVideoGetsBarsAboveAndBelow() {
    // 울트라와이드(21:9)를 4:3 아이패드 화면에: 위아래가 빈다
    let rect = ScreenGeometry.videoRect(video: CGSize(width: 1920, height: 804), in: CGSize(width: 1200, height: 900))
    #expect(rect.width == 1200)
    #expect(abs(rect.height - 502.5) < 0.01)
    #expect(abs(rect.minY - 198.75) < 0.01)
    #expect(rect.minX == 0)
}

@Test func tallVideoGetsBarsOnSides() {
    let rect = ScreenGeometry.videoRect(video: CGSize(width: 1000, height: 1000), in: CGSize(width: 1600, height: 800))
    #expect(rect == CGRect(x: 400, y: 0, width: 800, height: 800))
}

// MARK: - 터치 → 영상 안 0~1 위치

@Test func touchInsideVideoIsNormalized() throws {
    let view = CGSize(width: 1600, height: 800), video = CGSize(width: 1000, height: 1000)
    let p = try #require(ScreenGeometry.normalized(touch: CGPoint(x: 600, y: 200), view: view, video: video))
    #expect(p == CGPoint(x: 0.25, y: 0.25))
}

@Test func touchOnLetterboxIsNil() {
    let view = CGSize(width: 1600, height: 800), video = CGSize(width: 1000, height: 1000)
    #expect(ScreenGeometry.normalized(touch: CGPoint(x: 100, y: 400), view: view, video: video) == nil)
    #expect(ScreenGeometry.normalized(touch: CGPoint(x: 1500, y: 400), view: view, video: video) == nil)
}

@Test func zoomedTouchMapsBackToVideo() throws {
    // 화면 가운데 기준 2배 확대: 화면 가운데는 그대로 영상 가운데, 화면 왼쪽 위 끝은 영상 1/4 지점
    let view = CGSize(width: 1000, height: 1000), video = CGSize(width: 1000, height: 1000)
    let center = try #require(ScreenGeometry.normalized(touch: CGPoint(x: 500, y: 500), view: view, video: video, zoom: 2))
    #expect(center == CGPoint(x: 0.5, y: 0.5))
    let corner = try #require(ScreenGeometry.normalized(touch: CGPoint(x: 0, y: 0), view: view, video: video, zoom: 2))
    #expect(corner == CGPoint(x: 0.25, y: 0.25))
}

@Test func zoomedAndPannedTouchMapsBackToVideo() throws {
    // 2배 확대 후 오른쪽으로 500 옮김: 화면 왼쪽 끝이 영상 왼쪽 끝
    let view = CGSize(width: 1000, height: 1000), video = CGSize(width: 1000, height: 1000)
    let p = try #require(ScreenGeometry.normalized(touch: CGPoint(x: 0, y: 500), view: view, video: video,
                                                    zoom: 2, offset: CGSize(width: 500, height: 0)))
    #expect(p == CGPoint(x: 0, y: 0.5))
}

@Test func zoomedTouchOutsideVideoIsStillNil() {
    // 확대해도 레터박스 쪽을 누르면 nil
    let view = CGSize(width: 1600, height: 800), video = CGSize(width: 1000, height: 1000)
    #expect(ScreenGeometry.normalized(touch: CGPoint(x: 10, y: 400), view: view, video: video,
                                      zoom: 1.5, offset: CGSize(width: 300, height: 0)) == nil)
}

// MARK: - 확대 중 옮길 수 있는 만큼

@Test func panIsClampedToZoomedEdges() {
    let view = CGSize(width: 1000, height: 800)
    #expect(ScreenGeometry.clampOffset(CGSize(width: 900, height: -900), zoom: 2, view: view) == CGSize(width: 500, height: -400))
    #expect(ScreenGeometry.clampOffset(CGSize(width: 50, height: 50), zoom: 1, view: view) == .zero)
}

// MARK: - 0~1 위치 → 맥 전체 좌표

@Test func normalizedMapsIntoDisplayBounds() {
    let main = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    #expect(ScreenGeometry.global(normalized: CGPoint(x: 0.5, y: 0.25), display: main) == CGPoint(x: 1720, y: 360))
}

@Test func leftMonitorHasNegativeOrigin() {
    // 주 모니터 왼쪽에 놓인 맥북 화면은 x가 음수에서 시작한다
    let left = CGRect(x: -1512, y: 200, width: 1512, height: 982)
    #expect(ScreenGeometry.global(normalized: CGPoint(x: 0.5, y: 0.5), display: left) == CGPoint(x: -756, y: 691))
    #expect(ScreenGeometry.global(normalized: CGPoint(x: 0, y: 0), display: left) == CGPoint(x: -1512, y: 200))
}

@Test func farEdgeStaysOnSameMonitor() {
    // 1.0을 그대로 쓰면 옆 모니터 첫 칸이 된다. 마지막 칸에 머물게 한다
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    #expect(ScreenGeometry.global(normalized: CGPoint(x: 1, y: 1), display: main) == CGPoint(x: 1919, y: 1079))
    #expect(ScreenGeometry.global(normalized: CGPoint(x: 1.7, y: -0.3), display: main) == CGPoint(x: 1919, y: 0))
}

// MARK: - 영상 크기

@Test func ultrawideFitsIntoIPadSize() {
    let size = ScreenGeometry.fit(width: 3440, height: 1440, maxSide: 1920)
    #expect(size.width == 1920)
    #expect(size.height == 804)
}

@Test func fitKeepsEvenSizes() {
    // H.264 압축기는 짝수 크기를 좋아한다
    let size = ScreenGeometry.fit(width: 1512, height: 982, maxSide: 1280)
    #expect(size.width == 1280)
    #expect(size.height == 832)
}

@Test func fitNeverUpscales() {
    let size = ScreenGeometry.fit(width: 1280, height: 720, maxSide: 1920)
    #expect(size.width == 1280)
    #expect(size.height == 720)
}

@Test func fitClampsAbsurdRequests() {
    // 기기가 0이나 엄청 큰 값을 보내도 320~3840 안에서
    #expect(ScreenGeometry.fit(width: 3440, height: 1440, maxSide: 0).width == 320)
    #expect(ScreenGeometry.fit(width: 7680, height: 4320, maxSide: 100_000).width == 3840)
}

// MARK: - 두 손가락: 확대, 보는 위치 옮기기, 맥 스크롤

@Test func pinchBecomesZoom() {
    #expect(TwoFinger.decide(.undecided, scale: 1.1, moved: 0, zoom: 1) == .zoom)
}

@Test func swipeAtNormalSizeScrollsMac() {
    #expect(TwoFinger.decide(.undecided, scale: 1, moved: 13, zoom: 1) == .scroll)
}

@Test func swipeWhileZoomedMovesView() {
    #expect(TwoFinger.decide(.undecided, scale: 1, moved: 13, zoom: 2) == .pan)
}

@Test func smallMovesStayUndecided() {
    #expect(TwoFinger.decide(.undecided, scale: 1.05, moved: 10, zoom: 2) == .undecided)
}

@Test func decidedModeSticks() {
    // 스크롤로 정한 뒤 손가락 간격이 조금 변해도 확대로 바뀌지 않는다
    #expect(TwoFinger.decide(.scroll, scale: 1.3, moved: 40, zoom: 1) == .scroll)
    #expect(TwoFinger.decide(.pan, scale: 1.3, moved: 40, zoom: 2) == .pan)
}
