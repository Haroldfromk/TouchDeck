import SwiftUI

/// 밖에서 붙을 맥 주소(Tailscale)를 넣는 시트. 비워 두면 집에서만 쓴다
struct RemoteSettingsSheet: View {
    let client: DeckClient
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var reason: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("맥 주소", text: $address)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let reason {
                            Text(reason).foregroundStyle(DeckTheme.failure)
                        }
                        Text("Tailscale이 맥에 붙인 이름이나 100으로 시작하는 주소를 넣으세요. 비워 두면 집에서만 써요")
                    }
                }
            }
            .navigationTitle("밖에서 붙기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                }
            }
        }
        .onAppear { address = client.remoteHost ?? "" }
        .preferredColorScheme(.dark)
    }

    private func save() {
        reason = client.setRemoteHost(address)
        if reason == nil { dismiss() }
    }
}
