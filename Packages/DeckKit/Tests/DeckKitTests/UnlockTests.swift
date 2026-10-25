import Foundation
import Network
import Testing
@testable import DeckKit

// MARK: - 메시지와 기능 번호

@Test func unlockMessagesRoundTrip() throws {
    for message in [ServerMessage.lockState(locked: true, unlockAllowed: false), .unlockResult(.wrongPassword)] {
        #expect(try ServerMessage.decode(message.encoded()) == message)
    }
    #expect(try ClientMessage.decode(ClientMessage.unlock(password: "a").encoded()) == .unlock(password: "a"))
}

@Test func unlockPasswordRoundTripsAnyCharacters() throws {
    let password = #"p"a\ss 한글 👍🏽"#
    #expect(try ClientMessage.decode(ClientMessage.unlock(password: password).encoded()) == .unlock(password: password))
}

@Test func oldTrustedDeviceHasUnlockOff() throws {
    let json = #"{"id":"a","name":"iPhone","token":"t","screenAllowed":true}"#
    #expect(try JSONDecoder().decode(TrustedDevice.self, from: Data(json.utf8)).unlockAllowed == false)
}

@Test func unlockNeedsProtocolFour() {
    #expect(DeckProtocol.unlock == 4)
    #expect(DeckProtocol.current == DeckProtocol.unlock)
}

@Test func unlockAllowedFollowsSetter() {
    var authority = PairingAuthority(trusted: [TrustedDevice(id: "a", name: "iPad", token: "dA=="),
                                               TrustedDevice(id: "b", name: "iPhone", token: "dA==")])
    authority.setUnlockAllowed(true, deviceId: "b")
    #expect(authority.isUnlockAllowed(deviceId: "b"))
    #expect(!authority.isUnlockAllowed(deviceId: "a"))
    #expect(!authority.isUnlockAllowed(deviceId: "nobody"))
}
