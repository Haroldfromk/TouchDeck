import SwiftUI

@main
struct TouchDeckApp: App {
    @State private var client = DeckClient()

    var body: some Scene {
        WindowGroup {
            DeckView(client: client)
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
