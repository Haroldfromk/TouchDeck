import AppKit
import ApplicationServices
import DeckKit

/// 키보드의 볼륨 키를 누른 것과 같은 시스템 이벤트를 만든다.
/// 소리가 맥북 스피커로 나갈 땐 macOS가, DisplayPort 모니터로 나갈 땐 BetterDisplay가 이 신호를 받는다.
/// 이벤트를 보내려면 손쉬운 사용 권한이 필요하다.
enum MediaKey {
    /// macOS의 NX_KEYTYPE 값 (IOKit hidsystem/ev_keymap.h)
    static func code(for key: VolumeKey) -> Int32 {
        switch key {
        case .up: 0     // NX_KEYTYPE_SOUND_UP
        case .down: 1   // NX_KEYTYPE_SOUND_DOWN
        case .mute: 7   // NX_KEYTYPE_MUTE
        }
    }

    /// 시스템 이벤트의 data1: 위 16비트는 키 코드, 아래는 누름(0xA00) / 뗌(0xB00)
    static func data1(code: Int32, down: Bool) -> Int {
        Int((code << 16) | (down ? 0xA00 : 0xB00))
    }

    static var allowed: Bool { AXIsProcessTrusted() }

    /// 권한이 없으면 시스템 설정으로 안내하는 창을 한 번 띄운다
    static func requestPermissionIfNeeded() {
        let prompt = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// 누르고 떼기를 한 번. 권한이 없으면 false
    static func press(_ key: VolumeKey) -> Bool {
        guard allowed else { return false }
        let code = code(for: key)
        for down in [true, false] {
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1(code: code, down: down), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }
}
