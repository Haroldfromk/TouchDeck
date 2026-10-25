import Foundation
import Network
import Testing
@testable import DeckKit

// MARK: - 주소 다듬기와 VPN 경로

@Test func cleanStripsSchemePortAndSlash() {
    #expect(RemoteAddress.clean("  ws://dongiks-macbook-pro:52801/ ") == "dongiks-macbook-pro")
    #expect(RemoteAddress.clean("http://100.101.102.103") == "100.101.102.103")
    #expect(RemoteAddress.clean("macbook.tail1234.ts.net/") == "macbook.tail1234.ts.net")
}

@Test func rejectsEmptyAndSpaces() {
    #expect(RemoteAddress.clean("   ") == nil)
    #expect(RemoteAddress.clean("ws://") == nil)
    #expect(RemoteAddress.clean("my mac") == nil)
}

@Test func remoteURLUsesWebSocketPort() {
    #expect(RemoteAddress.url(host: "100.101.102.103")?.absoluteString == "ws://100.101.102.103:52801/")
}

@Test func utunIsVPN() {
    #expect(ConnectionRoute(interfaceName: "utun3", isWiFi: false, isWired: false) == .vpn)
    #expect(ConnectionRoute(interfaceName: "awdl0", isWiFi: true, isWired: false) == .direct)
    #expect(ConnectionRoute(interfaceName: "en0", isWiFi: true, isWired: false) == .sameWiFi)
    #expect(ConnectionRoute.vpn.label == "원격(VPN)")
}

// MARK: - 붙는 순서와 원격 화질

@Test func bonjourFirstNoWait() {
    #expect(RemotePlan.next(bonjourFound: true, waited: 0, remoteHost: "mac", localNetworkDenied: false) == .useBonjour)
    #expect(RemotePlan.next(bonjourFound: false, waited: 1, remoteHost: "mac", localNetworkDenied: false) == .keepSearching)
}

@Test func remoteAfterThreeSeconds() {
    #expect(RemotePlan.next(bonjourFound: false, waited: 3, remoteHost: "mac", localNetworkDenied: false) == .useRemote(host: "mac"))
    #expect(RemotePlan.next(bonjourFound: false, waited: 10, remoteHost: nil, localNetworkDenied: false) == .keepSearching)
}

@Test func deniedLocalNetworkStillUsesRemote() {
    #expect(RemotePlan.next(bonjourFound: false, waited: 0, remoteHost: "mac", localNetworkDenied: true) == .useRemote(host: "mac"))
}

@Test func vpnUsesRemotePreset() {
    let s = ScreenQuality.settings(route: .vpn, deviceLongSide: 2388, savedFPS: 60, savedAudio: true, remoteOverride: nil)
    #expect(s == ScreenSettings(maxSide: 1600, fps: 30, audio: false, bitrateCap: 4_000_000))
}

@Test func remoteOverrideDoesNotTouchSaved() {
    let s = ScreenQuality.settings(route: .vpn, deviceLongSide: 2388, savedFPS: 60, savedAudio: true, remoteOverride: (fps: 60, audio: true))
    #expect(s == ScreenSettings(maxSide: 1600, fps: 60, audio: true, bitrateCap: 4_000_000))
    let home = ScreenQuality.settings(route: .sameWiFi, deviceLongSide: 2388, savedFPS: 60, savedAudio: true, remoteOverride: (fps: 30, audio: false))
    #expect(home == ScreenSettings(maxSide: 2388, fps: 60, audio: true, bitrateCap: nil))
}

// MARK: - 비트레이트 상한 칸

@Test func bitrateCapRoundTrips() throws {
    let m = ClientMessage.startScreen(displayId: 1, maxSide: 1600, fps: 30, audio: false, bitrateCap: 4_000_000)
    #expect(try ClientMessage.decode(m.encoded()) == m)
    let o = ClientMessage.screenOptions(fps: 60, audio: true, bitrateCap: nil)
    #expect(try ClientMessage.decode(o.encoded()) == o)
    #expect(try !o.encoded().contains("bitrateCap"))
}

@Test func missingBitrateCapIsNil() throws {
    let old = #"{"type":"startScreen","displayId":7,"maxSide":2388,"fps":60,"audio":true}"#
    #expect(try ClientMessage.decode(old) == .startScreen(displayId: 7, maxSide: 2388, fps: 60, audio: true, bitrateCap: nil))
}

// MARK: - 맥이 정하는 길

/// 아이폰은 자기 쪽 장치 이름을 엉뚱하게 알려 줄 때가 있다(Tailscale은 pdp_ip0, 직접 연결은 기타).
/// 맥은 연결이 들어온 장치와 상대 주소를 정확히 알아서, 맥이 정한 길을 이름표로 쓴다
@Test func macRouteUsesTailscaleAddressFirst() throws {
    #expect(ConnectionRoute(interfaceName: "en0", isWiFi: true, isWired: false, remote: try #require(NWEndpoint.Host("100.64.0.1"))) == .vpn)
    #expect(ConnectionRoute(interfaceName: "utun10", isWiFi: false, isWired: false, remote: try #require(NWEndpoint.Host("fd7a:115c:a1e0::1"))) == .vpn)
    #expect(ConnectionRoute(interfaceName: "awdl0", isWiFi: true, isWired: false, remote: try #require(NWEndpoint.Host("fe80::1%awdl0"))) == .direct)
    #expect(ConnectionRoute(interfaceName: "en8", isWiFi: false, isWired: true, remote: try #require(NWEndpoint.Host("192.168.0.20"))) == .wired)
    #expect(ConnectionRoute(interfaceName: "en0", isWiFi: true, isWired: false, remote: nil) == .sameWiFi)
}

@Test func routeMessageRoundTrips() throws {
    for route in [ConnectionRoute.sameWiFi, .direct, .wired, .vpn, .other] {
        #expect(try ServerMessage.decode(ServerMessage.route(route).encoded()) == .route(route))
    }
}

@Test func routeFromMacNeedsProtocolFive() {
    #expect(DeckProtocol.routeFromMac == 5)
    #expect(DeckProtocol.current == DeckProtocol.routeFromMac)
}
