import DeckKit
import SwiftUI

/// 키캡 하나. 탭하면 맥에서 실행, 길게 누르면 편집.
struct ButtonTile: View {
    let button: DeckButton?
    let icon: UIImage?
    let failed: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    @State private var pressed = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let button {
                    keycap(button, side: side)
                } else {
                    socket(side: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .contentShape(.rect)
        .onTapGesture { button == nil ? onEdit() : onTap() }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onEdit()
        } onPressingChanged: { pressed = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(button?.label ?? "빈 칸")
        .accessibilityHint(button == nil ? "버튼 추가" : "맥에서 실행")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "편집", onEdit)
    }

    // MARK: - 키캡

    private func keycap(_ button: DeckButton, side: CGFloat) -> some View {
        let lip = side * 0.06
        let radius = side * 0.16
        return ZStack(alignment: .top) {
            // 아랫단: 누르면 윗면이 이만큼 내려앉는다
            RoundedRectangle(cornerRadius: radius)
                .fill(DeckTheme.keyLip)
                .offset(y: lip)

            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: [DeckTheme.keycapTop, DeckTheme.keycap], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(failed ? DeckTheme.failure : .white.opacity(0.06), lineWidth: failed ? 3 : 1)
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(DeckTheme.accent(for: button.action))
                        .frame(width: side * 0.07, height: side * 0.07)
                        .shadow(color: DeckTheme.accent(for: button.action).opacity(0.8), radius: pressed ? 6 : 3)
                        .padding(side * 0.1)
                }
                .overlay { legend(button, side: side) }
                .offset(y: pressed ? lip : 0)
        }
        .padding(.bottom, lip)
        .animation(.spring(duration: 0.12), value: pressed)
    }

    @ViewBuilder
    private func legend(_ button: DeckButton, side: CGFloat) -> some View {
        VStack(spacing: side * 0.06) {
            switch button.action {
            case .app:
                if let icon {
                    Image(uiImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side * 0.44, height: side * 0.44)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: side * 0.3))
                        .foregroundStyle(DeckTheme.legendDim)
                }
                Text(button.label)
                    .font(DeckTheme.legendFont(size: side * 0.12))
                    .foregroundStyle(DeckTheme.legend)
            case .command(let command, _, _):
                Image(systemName: "apple.terminal")
                    .font(.system(size: side * 0.2, weight: .medium))
                    .foregroundStyle(DeckTheme.command)
                Text(button.label)
                    .font(DeckTheme.legendFont(size: side * 0.12))
                    .foregroundStyle(DeckTheme.legend)
                if command != button.label {
                    Text(command)
                        .font(.system(size: side * 0.085, design: .monospaced))
                        .foregroundStyle(DeckTheme.legendDim)
                }
            case .terminal:
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: side * 0.22, weight: .medium))
                    .foregroundStyle(DeckTheme.terminal)
                Text(button.label)
                    .font(DeckTheme.legendFont(size: side * 0.12))
                    .foregroundStyle(DeckTheme.legend)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, side * 0.08)
    }

    // MARK: - 빈 칸 (키캡이 빠진 소켓)

    private func socket(side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.16)
            .fill(DeckTheme.socket)
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .foregroundStyle(.white.opacity(pressed ? 0.35 : 0.15))
            }
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: side * 0.16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.bottom, side * 0.06)
    }
}
