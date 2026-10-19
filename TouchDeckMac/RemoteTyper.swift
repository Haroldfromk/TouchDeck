import Carbon.HIToolbox
import CoreGraphics
import DeckKit
import Foundation

/// 보기 화면 특수 키 → 맥 키 번호와 같이 누를 키
enum RemoteKeys {
    static func stroke(for key: RemoteKey) -> (code: CGKeyCode, flags: CGEventFlags) {
        switch key {
        case .escape: (CGKeyCode(kVK_Escape), [])
        case .tab: (CGKeyCode(kVK_Tab), [])
        case .shiftTab: (CGKeyCode(kVK_Tab), .maskShift)
        case .up: (CGKeyCode(kVK_UpArrow), [])
        case .down: (CGKeyCode(kVK_DownArrow), [])
        case .left: (CGKeyCode(kVK_LeftArrow), [])
        case .right: (CGKeyCode(kVK_RightArrow), [])
        case .delete: (CGKeyCode(kVK_Delete), [])
        case .enter: (CGKeyCode(kVK_Return), [])
        case .controlC: (CGKeyCode(kVK_ANSI_C), .maskControl)
        case .selectAll: (CGKeyCode(kVK_ANSI_A), .maskCommand)
        }
    }
}

/// 맥에 넣을 입력 한 걸음: 글자 묶음(20자 이하) 또는 키 하나
enum RemoteStep: Equatable, Sendable {
    case text(String)
    case key(CGKeyCode, CGEventFlags)
}

/// 보기 화면에서 온 글과 키를 받은 순서대로 맥에 넣는다.
/// 한 줄로 세우니 "보내고 엔터"의 엔터가 긴 글보다 먼저 눌리지 않는다. 넣은 글자는 어디에도 남기지 않는다.
final class RemoteTyper: @unchecked Sendable {
    static let shared = RemoteTyper(post: RemoteTyper.postEvent, pause: { usleep(2_000) })

    private let queue = DispatchQueue(label: "touchdeck.typing")
    private let post: @Sendable (RemoteStep) -> Void
    private let pause: @Sendable () -> Void

    init(post: @escaping @Sendable (RemoteStep) -> Void, pause: @escaping @Sendable () -> Void) {
        self.post = post
        self.pause = pause
    }

    func type(_ text: String) {
        let chunks = TextInput.chunks(text)
        queue.async { [post, pause] in
            for (i, chunk) in chunks.enumerated() {
                // 묶음 사이에 아주 짧게 쉰다. 앱이 놓치지 않게
                if i > 0 { pause() }
                post(.text(chunk))
            }
        }
    }

    func press(_ key: RemoteKey) {
        let stroke = RemoteKeys.stroke(for: key)
        queue.async { [post] in post(.key(stroke.code, stroke.flags)) }
    }

    /// 테스트용: 앞에 넣은 것을 다 넣을 때까지 기다린다
    func waitUntilIdle() {
        queue.sync {}
    }

    /// 글자는 키 번호가 아니라 글자 그대로 싣는다. 그래서 맥 입력 상태가 한글이어도 쓴 글자가 들어간다
    private static func postEvent(_ step: RemoteStep) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            switch step {
            case .text(let chunk):
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                let units = Array(chunk.utf16)
                event?.flags = []
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event?.post(tap: .cghidEventTap)
            case .key(let code, let flags):
                let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
                // 맥에서 누르고 있는 다른 키는 섞지 않는다
                event?.flags = flags
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
