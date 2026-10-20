import AppKit
import IOKit.pwr_mgt

/// "잠자기 막기" 체크와 화면 보기 중인지에 따라 macOS에 들고 있을 요청을 정한다
enum KeepAwake {
    enum Kind: Hashable { case system, display }

    static let key = "keepAwake"

    /// 체크가 켜지면 시스템과 디스플레이 둘 다(디스플레이가 꺼지면 맥이 잠겨 밖에서 화면을 못 본다).
    /// 체크가 꺼져 있어도 보는 중이면 디스플레이만(보는 중에 꺼지면 찍을 화면이 사라진다)
    static func wanted(enabled: Bool, viewing: Bool) -> Set<Kind> {
        if enabled { return [.system, .display] }
        return viewing ? [.display] : []
    }
}

/// IOKit 전원 관리 요청을 실제로 들고 놓는 부분. 가만히 있어서 잠드는 것만 막는다(직접 잠자기, 덮개 닫기는 그대로)
@MainActor
final class PowerAssertions {
    private var held: [KeepAwake.Kind: IOPMAssertionID] = [:]

    func apply(_ wanted: Set<KeepAwake.Kind>) {
        for (kind, id) in held where !wanted.contains(kind) {
            IOPMAssertionRelease(id)
            held[kind] = nil
        }
        for kind in wanted where held[kind] == nil {
            let type = kind == .system ? kIOPMAssertionTypePreventUserIdleSystemSleep : kIOPMAssertionTypePreventUserIdleDisplaySleep
            let name = kind == .system ? "TouchDeck 잠자기 막기" : "TouchDeck 화면 보기"
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id) == kIOReturnSuccess {
                held[kind] = id
            } else {
                print("[power] assertion failed:", name)
            }
        }
    }
}

/// 체크(UserDefaults)와 보는 기기(ScreenHost.viewerName)를 지켜보다가 바뀌면 요청을 다시 맞춘다.
/// 메뉴 창이 닫혀 있어도 보는 기기는 바뀌므로 메뉴가 아니라 여기서 지켜본다
@MainActor
final class KeepAwakeController {
    private let power = PowerAssertions()
    private let screen: ScreenHost

    init(screen: ScreenHost) {
        self.screen = screen
        refresh()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.power.apply([]) }
        }
    }

    func refresh() {
        let viewing = withObservationTracking { screen.viewerName != nil } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        power.apply(KeepAwake.wanted(enabled: UserDefaults.standard.bool(forKey: KeepAwake.key), viewing: viewing))
    }
}
