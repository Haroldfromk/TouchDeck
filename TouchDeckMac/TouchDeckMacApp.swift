import DeckKit
import SwiftUI

@main
struct TouchDeckMacApp: App {
    @State private var server: DeckServer

    init() {
        // 터미널이 아닌 파일로 로그를 받을 때도 줄마다 바로 쓰이게
        setvbuf(stdout, nil, _IOLBF, 0)
        let server = DeckServer(store: Self.debugStore() ?? ConfigStore(), random: Self.debugRandom(), actions: LiveActions())
        // 단위 테스트가 이 앱을 띄울 때는 서버를 열지 않는다 (진짜 서버와 포트가 겹친다)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            server.start()
        }
        _server = State(initialValue: server)
    }

    /// 디버그 빌드에서 끝까지 확인할 때만: 설정 파일 위치를 바꿔 실제 설정에 테스트 버튼이 남지 않게.
    private static func debugStore() -> ConfigStore? {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["TOUCHDECK_DEBUG_CONFIG"] { return ConfigStore(url: URL(filePath: path)) }
        #endif
        return nil
    }

    /// 디버그 빌드에서 UI 테스트가 숫자를 알 수 있게 페어링 숫자를 고정한다.
    private static func debugRandom() -> (@Sendable () -> UInt32)? {
        #if DEBUG
        if let code = ProcessInfo.processInfo.environment["TOUCHDECK_DEBUG_PAIR_CODE"].flatMap(UInt32.init) { return { code } }
        #endif
        return nil
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(server: server)
        } label: {
            Image(systemName: server.pairingCode == nil ? "square.grid.3x3.fill" : "number.square.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

/// 실제 맥에서 버튼을 실행한다. 느린 일(앱 아이콘 만들기, osascript)은 메인 스레드 밖에서.
@MainActor
final class LiveActions: DeckActions {
    private let runner = ActionRunner.live
    private var cachedApps: [AppInfo]?

    func run(_ action: ButtonAction) async -> (ok: Bool, message: String?) {
        await runner.run(action)
    }

    func apps() async -> [AppInfo] {
        if let cachedApps { return cachedApps }
        let apps = await Task.detached { AppCatalog.scan() }.value
        cachedApps = apps
        return apps
    }

    func volume() async -> (value: Int, muted: Bool, available: Bool) {
        await Task.detached { VolumeController.get() }.value
    }

    func setVolume(_ value: Int) async {
        await Task.detached { VolumeController.set(value) }.value
    }
}
