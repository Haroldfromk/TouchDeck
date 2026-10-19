import Carbon.HIToolbox
import CoreGraphics
import DeckKit

/// 키패드에서 누른 키를 맥에서 앞에 떠 있는 앱에 그 키를 누른 것처럼 입력한다.
/// 볼륨 키와 같은 손쉬운 사용 권한을 쓴다. 누른 키는 어디에도 남기지 않는다.
enum KeyTyper {
    /// 맥 키보드의 키 번호. 숫자는 윗줄 숫자 키라 한글 입력 상태여도 숫자가 들어간다.
    static func keyCode(for key: TypedKey) -> CGKeyCode? {
        switch key {
        case .digit(let d):
            let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                          kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
            return digits.indices.contains(d) ? CGKeyCode(digits[d]) : nil
        case .tab: return CGKeyCode(kVK_Tab)
        case .delete: return CGKeyCode(kVK_Delete)
        case .enter: return CGKeyCode(kVK_Return)
        }
    }

    /// 누르고 떼기를 한 번. 권한이 없거나 모르는 키면 false
    static func type(_ key: TypedKey) -> Bool {
        guard MediaKey.allowed, let code = keyCode(for: key) else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            // 맥에서 Shift 같은 걸 누르고 있어도 키패드 키만 들어가게
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        return true
    }
}
