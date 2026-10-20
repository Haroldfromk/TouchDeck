import DeckKit
import SwiftUI

/// 위쪽 한 줄 상태. 연결됐을 땐 조용히, 안 됐을 땐 무엇을 해야 하는지 알려준다.
struct ConnectionStatusView: View {
    let phase: DeckClient.Phase
    var route: ConnectionRoute?
    var remoteFailed = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: 4)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DeckTheme.legend)
            if case .connected = phase, let route {
                Label(route.label, systemImage: route.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DeckTheme.legendDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DeckTheme.socket, in: .capsule)
            }
            Spacer()
            if case .localNetworkDenied = phase {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .frame(height: 24)
    }

    private var phaseText: String {
        switch phase {
        case .searching: "같은 와이파이에서 맥을 찾는 중 (맥에서 TouchDeck을 켜 두세요)"
        case .connecting(let name): "\(name)에 연결하는 중"
        case .needsPairing(let name), .pairingFailed(let name, _): "\(name)의 허락을 기다리는 중"
        case .pairingLocked(let name): "\(name)에서 새 기기 허락이 멈춰 있어요"
        case .connected(let name): "\(name)에 연결됨"
        case .localNetworkDenied: "로컬 네트워크 권한이 꺼져 있어요. 설정 > 개인정보 보호 및 보안 > 로컬 네트워크에서 TouchDeck을 켜세요"
        case .needsHomePairing: "집 와이파이에서 먼저 허락받아 주세요"
        }
    }

    private var text: String {
        switch phase {
        case .searching, .connecting:
            remoteFailed ? "밖에서 맥에 붙지 못했어요. 아이패드와 맥에서 Tailscale이 켜져 있는지 확인해 주세요" : phaseText
        default: phaseText
        }
    }

    private var color: Color {
        switch phase {
        case .connected: DeckTheme.command
        case .localNetworkDenied, .needsHomePairing: DeckTheme.failure
        default: DeckTheme.terminal
        }
    }
}
