import DeckKit
import SwiftUI

/// 메뉴바 아이콘을 누르면 뜨는 작은 창. 편집 화면은 두지 않는다 (편집은 아이패드/아이폰에서).
struct MenuContent: View {
    let server: DeckServer
    var loginItem = LoginItem.live
    @State private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(server.status, systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)

            if let code = server.pairingCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(server.pairingDeviceName ?? "새 기기")에 이 숫자를 입력하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .tracking(6)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15), in: .rect(cornerRadius: 8))
            }

            if server.isPairingLocked {
                VStack(alignment: .leading, spacing: 6) {
                    Text("페어링 숫자가 \(PairingAuthority.maxAttempts)번 틀려서 새 기기 허락을 멈췄어요.")
                        .font(.caption)
                    Button("새 기기 허락 다시 받기") { server.unlockPairing() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.12), in: .rect(cornerRadius: 8))
            }

            section("연결된 기기") {
                if server.connectedDevices.isEmpty {
                    Text("없음").foregroundStyle(.secondary)
                } else {
                    ForEach(server.connectedDevices, id: \.self) { Text($0) }
                }
            }

            section("허락한 기기") {
                if server.trusted.isEmpty {
                    Text("없음").foregroundStyle(.secondary)
                } else {
                    ForEach(server.trusted, id: \.id) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            Button("허락 취소") { server.revoke(deviceId: device.id) }
                                .controlSize(.small)
                        }
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        loginError = loginItem.set(on)
                        launchAtLogin = loginItem.isOn
                    }
                ))
                if let note = loginError ?? (launchAtLogin ? loginItem.note : nil) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("TouchDeck 종료") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
        // 시스템 설정에서 바꿨을 수도 있으니 창을 열 때마다 다시 읽는다
        .onAppear { launchAtLogin = loginItem.isOn }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
