import Carbon.HIToolbox
import DeckKit
import Testing
@testable import TouchDeck

/// 키패드 키를 맥 키보드의 실제 키 번호로. 숫자는 윗줄 숫자 키(한글 입력 상태여도 숫자가 들어간다)
@Test func digitsMapToTopRowKeys() {
    let expected = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                    kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    for (digit, code) in expected.enumerated() {
        #expect(KeyTyper.keyCode(for: .digit(digit)) == CGKeyCode(code))
    }
}

@Test func editingKeysMap() {
    #expect(KeyTyper.keyCode(for: .tab) == CGKeyCode(kVK_Tab))
    #expect(KeyTyper.keyCode(for: .delete) == CGKeyCode(kVK_Delete))
    #expect(KeyTyper.keyCode(for: .enter) == CGKeyCode(kVK_Return))
}

@Test func outOfRangeDigitHasNoKey() {
    #expect(KeyTyper.keyCode(for: .digit(12)) == nil)
}
