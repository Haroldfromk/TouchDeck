import AppKit
import CoreGraphics

/// 맥 앱의 화면 기록 권한. 손쉬운 사용과 따로 받는다.
enum ScreenPermission {
    static var granted: Bool { CGPreflightScreenCaptureAccess() }

    /// 아직 묻지 않았으면 시스템이 묻는 창을 띄운다 (한 번만 뜬다)
    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 맥이 잠겼거나 화면 보호기가 돌고 있으면 화면도 입력도 보내지 않는다.
enum ScreenLock {
    static var isLocked: Bool {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true {
            return true
        }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.ScreenSaver.Engine" }
    }
}
