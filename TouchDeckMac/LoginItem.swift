import Foundation
import ServiceManagement

/// 로그인할 때 맥 앱을 자동으로 띄운다. 실제 등록은 SMAppService.mainApp이 하고,
/// 테스트에서 해롤드의 로그인 항목을 건드리지 않게 클로저로 받는다.
struct LoginItem: Sendable {
    var status: @Sendable () -> SMAppService.Status
    var register: @Sendable () throws -> Void
    var unregister: @Sendable () throws -> Void
    var bundlePath: String

    /// 등록은 됐는데 시스템 설정에서 허용을 기다리는 중이어도 켠 것으로 보여 준다 (안내가 같이 뜬다)
    var isOn: Bool { [.enabled, .requiresApproval].contains(status()) }

    /// 토글 아래에 덧붙일 안내. 할 일이 없으면 nil
    var note: String? {
        if status() == .requiresApproval { return "시스템 설정 > 일반 > 로그인 항목에서 TouchDeck을 허용해 주세요" }
        // 등록은 지금 실행 중인 앱 경로로 된다. Xcode에서 띄운 빌드를 등록하면 로그인 때 그 빌드가 뜬다
        if !bundlePath.hasPrefix("/Applications/") { return "/Applications에 설치한 TouchDeck에서 켜야 다음 로그인에도 그 앱이 떠요" }
        return nil
    }

    /// 켜거나 끈다. 실패하면 이유를 돌려준다
    func set(_ on: Bool) -> String? {
        do {
            try on ? register() : unregister()
            return nil
        } catch {
            return "로그인 항목 \(on ? "등록" : "해제") 실패: \(error.localizedDescription)"
        }
    }

    static let live = LoginItem(
        status: { SMAppService.mainApp.status },
        register: { try SMAppService.mainApp.register() },
        unregister: { try SMAppService.mainApp.unregister() },
        bundlePath: Bundle.main.bundlePath
    )

    /// 아무것도 안 하는 가짜. 테스트에서 필요한 것만 바꿔 쓴다.
    static func fake() -> LoginItem {
        LoginItem(status: { .notRegistered }, register: {}, unregister: {}, bundlePath: "/Applications/TouchDeck.app")
    }
}
