import Testing
@testable import DeckKit

@Test func awdlIsDirect() {
    // 에어드롭이 쓰는 기기끼리 직접 연결 장치. 와이파이 무선이지만 공유기를 거치지 않는다
    #expect(ConnectionRoute(interfaceName: "awdl0", isWiFi: true, isWired: false) == .direct)
    #expect(ConnectionRoute(interfaceName: "llw0", isWiFi: true, isWired: false) == .direct)
}

@Test func normalWiFiIsSameNetwork() {
    #expect(ConnectionRoute(interfaceName: "en0", isWiFi: true, isWired: false) == .sameWiFi)
}

@Test func wiredAndUnknown() {
    #expect(ConnectionRoute(interfaceName: "en5", isWiFi: false, isWired: true) == .wired)
    #expect(ConnectionRoute(interfaceName: nil, isWiFi: false, isWired: false) == .other)
}

@Test func routeLabels() {
    #expect(ConnectionRoute.sameWiFi.label == "같은 와이파이")
    #expect(ConnectionRoute.direct.label == "직접 연결")
}
