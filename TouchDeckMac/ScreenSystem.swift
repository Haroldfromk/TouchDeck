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

    /// 잠금 풀기용: 시스템이 "화면 잠김"이라고 할 때만 true. 화면 보호기만 도는 건 넣지 않는다.
    /// 암호 없이 깨어나는 화면 보호기에 비밀번호를 치면, 첫 입력에 보호기가 걷히고 나머지가 앞의 앱에 들어간다
    static var isPasswordLocked: Bool {
        passwordLocked(session: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    static let lockedNotification = "com.apple.screenIsLocked"
    static let unlockedNotification = "com.apple.screenIsUnlocked"

    /// 잠김/풀림 알림이 온 순간에는 CGSession 값이 아직 바뀌기 전일 수 있다(풀렸는데 잠김으로 읽힘).
    /// 그래서 알림 이름으로 정한다. 모르는 알림이면 nil
    static func locked(afterNotification name: String) -> Bool? {
        switch name {
        case lockedNotification: true
        case unlockedNotification: false
        default: nil
        }
    }

    static func passwordLocked(session: [String: Any]?) -> Bool {
        (session?["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true
    }
}
