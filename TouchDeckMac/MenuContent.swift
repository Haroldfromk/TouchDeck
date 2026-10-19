import SwiftUI

/// 메뉴바 아이콘을 누르면 뜨는 작은 창. 편집 화면은 두지 않는다 (편집은 아이패드/아이폰에서).
struct MenuContent: View {
    let server: DeckServer

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
            Button("TouchDeck 종료") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
