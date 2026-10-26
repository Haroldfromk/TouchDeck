import AppKit
import DeckKit

/// 맥 메뉴에서 고른 터미널. 설치된 터미널은 번들 ID로 찾는다(~/Applications에 깐 것도 찾는다)
enum TerminalSettings {
    static let key = "terminalApp"

    static var saved: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// 지원 목록 중 설치된 터미널과 그 앱 위치
    static func installed() -> [TerminalApp: URL] {
        var found: [TerminalApp: URL] = [:]
        for app in TerminalApp.allCases {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) { found[app] = url }
        }
        return found
    }

    static func resolve() -> TerminalResolution {
        let installed = installed()
        switch TerminalApp.choose(saved: saved, installed: Set(installed.keys)) {
        case .use(let app):
            guard let url = installed[app] else { return .missing(app) }
            return .ready(app, appPath: url.path)
        case .missing(let app):
            return .missing(app)
        }
    }
}
