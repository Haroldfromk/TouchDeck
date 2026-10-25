import Carbon.HIToolbox
import CoreGraphics

/// 맥 화면을 잠근다. macOS 화면 잠금 단축키 ⌃⌘Q를 누른 것처럼 보낸다(손쉬운 사용 권한)
enum MacLocker {
    static let stroke = RemoteStep.key(CGKeyCode(kVK_ANSI_Q), [.maskControl, .maskCommand])

    /// 권한이 없어 못 보냈으면 false
    static func lock() -> Bool {
        guard MediaKey.allowed else { return false }
        RemoteTyper.postEvent(stroke)
        return true
    }
}
