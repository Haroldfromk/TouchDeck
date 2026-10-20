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
