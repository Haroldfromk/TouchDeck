import SwiftUI

/// 맥이 잠겨 있고, 가까이서 붙어 있고, 맥 메뉴에서 허용한 기기면 화면 아래에 "맥 잠금 풀기"를 겹쳐 띄운다.
/// 뒤의 화면(스트림덱, 키패드, 맥 화면)은 그대로 쓸 수 있다
struct UnlockOverlay: View {
    @Bindable var client: DeckClient

    var body: some View {
        VStack(spacing: 8) {
            if client.showsUnlock {
                if case .failed(let text) = client.unlockStatus {
                    HStack(spacing: 10) {
                        Text(text)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DeckTheme.legend)
                        // 맥은 이미 풀렸는데 버튼이 남아 있을 때처럼, 연결이 의심스러우면 직접 다시 붙는다
                        Button("다시 연결") { client.reconnectNow() }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(KeyPressStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DeckTheme.socket, in: .capsule)
                }
                Button {
                    Task { await client.unlockMac() }
                } label: {
                    Label(client.unlockStatus == .working ? "푸는 중" : "맥 잠금 풀기", systemImage: "lock.open.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(DeckTheme.command, in: .capsule)
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                }
                .buttonStyle(KeyPressStyle())
                .disabled(client.unlockStatus == .working)
                // 맥 비밀번호를 바꿨을 때
                .contextMenu {
                    Button("다시 연결", systemImage: "arrow.clockwise") { client.reconnectNow() }
                    Button("비밀번호 바꾸기", systemImage: "key") { client.needsMacPassword = true }
                    Button("비밀번호 지우기", systemImage: "trash", role: .destructive) { client.deleteMacPassword() }
                }
            }
        }
        .padding(.bottom, 28)
        .animation(.spring(duration: 0.25), value: client.showsUnlock)
        .sheet(isPresented: $client.needsMacPassword) { MacPasswordSheet(client: client) }
    }
}

/// 맥 비밀번호를 한 번 넣는다. 이 아이폰 키체인에만 저장되고, 꺼낼 때마다 Face ID를 거친다
private struct MacPasswordSheet: View {
    let client: DeckClient
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var reason: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("맥 비밀번호", text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let reason {
                            Text(reason).foregroundStyle(DeckTheme.failure)
                        }
                        Text("이 아이폰에만 저장되고 꺼낼 때마다 Face ID를 거쳐요")
                    }
                }
            }
            .navigationTitle("맥 비밀번호")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save).disabled(password.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard !password.isEmpty else { return }
        reason = client.saveMacPassword(password)
        guard reason == nil else { return }
        password = ""
        dismiss()
        // 저장하고 바로 풀기로 이어 간다
        Task { await client.unlockMac() }
    }
}
