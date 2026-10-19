import DeckKit
import SwiftUI

/// 숫자 키패드. 무각 키보드로 숫자 치기 어려울 때(로그인, 비밀번호 등) 쓴다.
/// 누른 키는 맥에서 앞에 떠 있는 앱에 입력되고, 이 화면에는 친 숫자를 보여주지 않는다.
struct KeypadView: View {
    let client: DeckClient

    private let rows: [[TypedKey]] = [
        [.digit(7), .digit(8), .digit(9)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(1), .digit(2), .digit(3)],
        [.tab, .digit(0), .delete],
    ]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            // 3열, 숫자 4줄 + Enter 1줄이 화면에 다 들어가는 가장 큰 정사각형 키
            let side = min((geo.size.width - spacing * 2) / 3, (geo.size.height - spacing * 4) / 5)
            VStack(spacing: spacing) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(rows[r], id: \.self) { key in
                            KeypadKey(key: key, onPress: client.typeKey)
                                .frame(width: side, height: side)
                        }
                    }
                }
                KeypadKey(key: .enter, onPress: client.typeKey)
                    .frame(width: side * 3 + spacing * 2, height: side)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct KeypadKey: View {
    let key: TypedKey
    let onPress: (TypedKey) -> Void

    @State private var pressed = false
    /// 짧게 탭해도 눌림이 보이게 (아이패드는 진동이 없다)
    @State private var tapFlash = false
    private var down: Bool { pressed || tapFlash }
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lip = side * 0.06
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: side * 0.16).fill(DeckTheme.keyLip).offset(y: lip)
                RoundedRectangle(cornerRadius: side * 0.16)
                    .fill(LinearGradient(colors: [DeckTheme.keycapTop, DeckTheme.keycap], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.16).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                    .overlay { RoundedRectangle(cornerRadius: side * 0.16).fill(.white.opacity(down ? 0.09 : 0)) }
                    .overlay { legend(side: side) }
                    .offset(y: down ? lip : 0)
            }
            .padding(.bottom, lip)
            .animation(.spring(duration: 0.1), value: down)
        }
        .contentShape(.rect)
        .onTapGesture {
            haptic.impactOccurred()
            tapFlash = true
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                tapFlash = false
            }
            onPress(key)
        }
        .onLongPressGesture(minimumDuration: 10) {} onPressingChanged: { pressed = $0 }
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPress(key) }
    }

    @ViewBuilder
    private func legend(side: CGFloat) -> some View {
        switch key {
        case .digit(let d):
            Text("\(d)").font(.system(size: side * 0.38, weight: .semibold, design: .rounded)).foregroundStyle(DeckTheme.legend)
        case .tab:
            symbolLegend("arrow.right.to.line", "Tab", side: side)
        case .delete:
            symbolLegend("delete.left", "지우기", side: side)
        case .enter:
            symbolLegend("return", "Enter", side: side)
        }
    }

    private func symbolLegend(_ symbol: String, _ text: String, side: CGFloat) -> some View {
        VStack(spacing: side * 0.05) {
            Image(systemName: symbol).font(.system(size: side * 0.24, weight: .semibold))
            Text(text).font(DeckTheme.legendFont(size: side * 0.11))
        }
        .foregroundStyle(DeckTheme.legendDim)
    }

    private var accessibilityName: String {
        switch key {
        case .digit(let d): "\(d)"
        case .tab: "Tab"
        case .delete: "지우기"
        case .enter: "Enter"
        }
    }
}
