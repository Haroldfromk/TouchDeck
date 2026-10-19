import DeckKit
import Testing
@testable import TouchDeck

/// 키보드의 볼륨 키와 같은 신호. macOS의 NX_KEYTYPE 값: 소리 올림 0, 내림 1, 음소거 7
@Test func volumeKeysMapToSystemKeyCodes() {
    #expect(MediaKey.code(for: .up) == 0)
    #expect(MediaKey.code(for: .down) == 1)
    #expect(MediaKey.code(for: .mute) == 7)
}

/// 시스템 이벤트 data1 = (키 코드 << 16) | (누름 0xA00 /뗌 0xB00)
@Test func data1PacksKeyAndState() {
    #expect(MediaKey.data1(code: 0, down: true) == 0x0000_0A00)
    #expect(MediaKey.data1(code: 1, down: false) == 0x0001_0B00)
    #expect(MediaKey.data1(code: 7, down: true) == 0x0007_0A00)
}
