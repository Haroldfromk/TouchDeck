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
    // Tailscale 주소면 어느 장치로 들어왔든 원격
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("100.64.0.1")), link: nil, linkIsLocalOnly: false) == .vpn)
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("fd7a:115c:a1e0::1")), link: "utun10", linkIsLocalOnly: false) == .vpn)
    // 상대 주소가 직접 연결 장치에 붙어 있으면 직접 연결
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("fe80::1")), link: "awdl0", linkIsLocalOnly: true) == .direct)
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("fe80::1")), link: "llw0", linkIsLocalOnly: true) == .direct)
    // 맥이 랜선(en8)이든 와이파이(en0)든 같은 네트워크. 와이파이인지 유선인지는 기기가 정한다
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("fe80::1")), link: "en8", linkIsLocalOnly: false) == .sameWiFi)
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("192.168.0.20")), link: nil, linkIsLocalOnly: false) == .sameWiFi)
    // Xcode가 케이블로 여는 통로(utun)도 Tailscale 주소가 아니면 같은 네트워크
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("fd08:d1fb:d78c::1")), link: "utun12", linkIsLocalOnly: false) == .sameWiFi)
}

/// 아이폰을 케이블로 꽂으면 맥에 en7 같은 장치가 생기고, 거기엔 169.254와 fe80 같은 근처 전용 주소만 있다.
/// 집 네트워크 주소가 없는 장치로 들어온 연결은 케이블로 바로 붙은 것이다
@Test func cableLinkIsWired() throws {
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("fe80::1")), link: "en7", linkIsLocalOnly: true) == .wired)
    // 직접 연결(awdl)도 근처 전용 주소만 있지만 무선이다
    #expect(ConnectionRoute(macSideRemote: try #require(NWEndpoint.Host("fe80::1")), link: "awdl0", linkIsLocalOnly: true) == .direct)
}

/// 맥이 같은 네트워크라고 하면 기기 쪽의 와이파이/유선 판단을 쓴다. 직접 연결과 원격은 맥 판단이 이긴다
@Test func deviceRouteCombinesMacAndLocal() {
    #expect(ConnectionRoute.shown(mac: .direct, local: .other) == .direct)
    #expect(ConnectionRoute.shown(mac: .vpn, local: .wired) == .vpn)
    #expect(ConnectionRoute.shown(mac: .sameWiFi, local: .wired) == .wired)
    #expect(ConnectionRoute.shown(mac: .sameWiFi, local: .sameWiFi) == .sameWiFi)
    #expect(ConnectionRoute.shown(mac: .sameWiFi, local: .other) == .sameWiFi)
    #expect(ConnectionRoute.shown(mac: nil, local: .other) == .other)
}

@Test func routeMessageRoundTrips() throws {
    for route in [ConnectionRoute.sameWiFi, .direct, .wired, .vpn, .other] {
        #expect(try ServerMessage.decode(ServerMessage.route(route).encoded()) == .route(route))
    }
}

@Test func routeFromMacNeedsProtocolFive() {
    #expect(DeckProtocol.routeFromMac == 5)
    #expect(DeckProtocol.current >= DeckProtocol.routeFromMac)
}
