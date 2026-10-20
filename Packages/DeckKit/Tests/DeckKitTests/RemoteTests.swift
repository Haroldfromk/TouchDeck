import Foundation
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
