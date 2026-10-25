import SwiftUI

@main
struct TouchDeckApp: App {
    @State private var client = DeckClient()

    var body: some Scene {
        WindowGroup {
            DeckView(client: client)
                // 맥 화면 보기는 전체 화면으로 덮으니 그 안에도 따로 붙인다
                .overlay(alignment: .bottom) { UnlockOverlay(client: client) }
                .sheet(isPresented: needsPairing) { PairingView(client: client) }
                .task { client.start() }
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
                // 책상 위에 세워 두는 기기라 화면이 꺼지지 않게
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }

    private var needsPairing: Binding<Bool> {
        Binding {
            switch client.phase {
            case .needsPairing, .pairingFailed, .pairingLocked: true
            default: false
            }
        } set: { _ in }
    }
}
