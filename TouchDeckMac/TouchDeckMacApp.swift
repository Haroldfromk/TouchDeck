import DeckKit
import SwiftUI

@main
struct TouchDeckMacApp: App {
    @State private var server: DeckServer

    init() {
        // 터미널이 아닌 파일로 로그를 받을 때도 줄마다 바로 쓰이게
        setvbuf(stdout, nil, _IOLBF, 0)
        let server = DeckServer(actions: StubActions())
        server.start()
        _server = State(initialValue: server)
    }

    var body: some Scene {
        MenuBarExtra("TouchDeck", systemImage: "square.grid.3x3.fill") {
            Text(server.status)
            if let code = server.pairingCode { Text("페어링 숫자: \(code)") }
        }
    }
}

/// Task 4에서 실제 실행기로 바뀐다.
struct StubActions: DeckActions {
    func run(_ action: ButtonAction) async -> (ok: Bool, message: String?) { (false, "준비 중") }
    func apps() async -> [AppInfo] { [] }
    func volume() async -> (value: Int, muted: Bool) { (50, false) }
    func setVolume(_ value: Int) async {}
}
