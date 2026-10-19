import DeckKit
import SwiftUI

@main
struct TouchDeckMacApp: App {
    @State private var server: DeckServer

    init() {
        // 터미널이 아닌 파일로 로그를 받을 때도 줄마다 바로 쓰이게
        setvbuf(stdout, nil, _IOLBF, 0)
        let server = DeckServer(actions: LiveActions())
        // 단위 테스트가 이 앱을 띄울 때는 서버를 열지 않는다 (진짜 서버와 포트가 겹친다)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            server.start()
        }
        _server = State(initialValue: server)
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
