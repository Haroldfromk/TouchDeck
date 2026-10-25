import DeckKit
import SwiftUI

/// 위쪽 한 줄 상태. 연결됐을 땐 조용히, 안 됐을 땐 무엇을 해야 하는지 알려준다.
struct ConnectionStatusView: View {
    let phase: DeckClient.Phase
    var route: ConnectionRoute?
    var remoteFailed = false
    /// 연결돼 있지만 맥이 잠겨 있다. 버튼들은 흐려진다
    var macLocked = false
    /// 밖에서 붙을 맥 주소를 넣는 시트를 연다
    var onRemote: (() -> Void)?

    /// 아이폰 세로처럼 좁은 화면. 연결돼 있으면 글 대신 아이콘만 보인다
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    private var connected: Bool {
        if case .connected = phase { return true }
        return false
    }
    /// 연결된 평소 상태(잠김 포함)는 아이콘만. 찾는 중이나 오류는 무엇을 할지 알려야 해서 글을 남긴다
    private var iconOnly: Bool { compact && connected }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color, radius: 4)
                .accessibilityLabel(text)
            if iconOnly {
                if macLocked {
                    Image(systemName: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DeckTheme.terminal)
                        .accessibilityHidden(true)
                }
            } else {
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DeckTheme.legend)
                    // 좁은 화면에서 안내 글이 잘리지 않게 두 줄까지
                    .lineLimit(compact ? 2 : 1)
            }
            if connected, let route {
                Group {
                    if iconOnly {
                        Image(systemName: route.symbol)
                    } else {
                        Label(route.label, systemImage: route.symbol)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(DeckTheme.legendDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DeckTheme.socket, in: .capsule)
                .accessibilityLabel(route.label)
            }
            Spacer()
            if case .localNetworkDenied = phase {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.subheadline.weight(.semibold))
            }
            if let onRemote {
                Button(action: onRemote) {
                    if compact {
                        Image(systemName: "globe")
                    } else {
                        Label("밖에서 붙기", systemImage: "globe")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("밖에서 붙기")
            }
        }
        .frame(minHeight: 24)
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
        case .connected where macLocked:
            "맥이 잠겨 있어요. 잠금을 풀면 다시 쓸 수 있어요"
        default: phaseText
        }
    }

    private var color: Color {
        switch phase {
        case .connected where macLocked: DeckTheme.terminal
        case .connected: DeckTheme.command
        case .localNetworkDenied, .needsHomePairing: DeckTheme.failure
        default: DeckTheme.terminal
        }
    }
}
