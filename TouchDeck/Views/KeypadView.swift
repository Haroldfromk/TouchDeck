import DeckKit
import SwiftUI

/// 숫자 키패드. 무각 키보드로 숫자 치기 어려울 때(로그인, 비밀번호 등) 쓴다.
/// 누른 키는 맥에서 앞에 떠 있는 앱에 입력되고, 이 화면에는 친 숫자를 보여주지 않는다.
struct KeypadView: View {
    let client: DeckClient
    /// 기호 화면: HHKB 무각에서 찾기 어려운 기호. 숫자 화면과 바꿔 가며 쓴다
    @State private var showSymbols = false

    private let digitRows: [[TypedKey]] = [
        [.digit(7), .digit(8), .digit(9)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(1), .digit(2), .digit(3)],
        [.tab, .digit(0), .delete],
    ]

    /// 4열 4줄. 위 두 줄은 HHKB 오른쪽 위 키와 그 Shift, 아래 두 줄은 괄호와 따옴표
    private var symbolRows: [[TypedKey]] {
        stride(from: 0, to: TypedKey.symbols.count, by: 4).map { start in
            TypedKey.symbols[start..<start + 4].map(TypedKey.symbol)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            let columns = CGFloat(showSymbols ? 4 : 3)
            // 키 4줄 + Enter 줄이 화면에 다 들어가는 가장 큰 정사각형 키
            let side = min((geo.size.width - spacing * (columns - 1)) / columns, (geo.size.height - spacing * 4) / 5)
            VStack(spacing: spacing) {
                let rows = showSymbols ? symbolRows : digitRows
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: spacing) {
                        ForEach(rows[r], id: \.self) { key in
                            KeypadKey(key: key, onPress: client.typeKey)
                                .frame(width: side, height: side)
                        }
                    }
                }
                HStack(spacing: spacing) {
                    ModeKey(title: showSymbols ? "123" : "기호", enabled: showSymbols || client.canTypeSymbols) {
                        showSymbols.toggle()
                    }
                    .frame(width: side, height: side)
                    if showSymbols {
                        KeypadKey(key: .delete, onPress: client.typeKey)
                            .frame(width: side, height: side)
                    }
                    KeypadKey(key: .enter, onPress: client.typeKey)
                        .frame(width: side * (columns - (showSymbols ? 2 : 1)) + spacing * (columns - (showSymbols ? 3 : 2)), height: side)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 맥이 예전 버전으로 바뀌었으면 숫자 화면으로 돌아온다
        .onChange(of: client.canTypeSymbols) { _, can in
            if !can { showSymbols = false }
        }
    }
}

/// 숫자 화면과 기호 화면을 바꾸는 키. 맥이 기호를 모르는 예전 버전이면 흐리게
private struct ModeKey: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                RoundedRectangle(cornerRadius: side * 0.16)
                    .fill(DeckTheme.socket)
                    .overlay(RoundedRectangle(cornerRadius: side * 0.16).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                    .overlay {
                        Text(title)
                            .font(DeckTheme.legendFont(size: side * 0.2))
                            .foregroundStyle(DeckTheme.legendDim)
                    }
            }
            .contentShape(.rect)
        }
        .buttonStyle(KeyPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title == "기호" ? "기호 화면" : "숫자 화면")
        .accessibilityHint(enabled ? "" : "맥 TouchDeck을 새 버전으로 설치해야 쓸 수 있어요")
    }
}

private struct KeypadKey: View {
    let key: TypedKey
    let onPress: (TypedKey) -> Void

    @State private var pressed = false
    /// 짧게 탭해도 눌림이 보이게 (아이패드는 진동이 없다)
    @State private var tapFlash = false
    /// ⌫를 누르고 있는 중. 손을 떼면 저절로 false가 돼서 지우기가 멈추지 않는 일이 없다
    @GestureState private var holding = false
    @State private var repeater: Task<Void, Never>?
    private var down: Bool { pressed || tapFlash || holding }
    @State private var haptic = PressHaptic()

    var body: some View {
        Group {
            if key == .delete {
                // 맥 키보드처럼 0.4초 누르고 있으면 뗄 때까지 연달아 지운다 (화면 보기 입력칸의 ⌫와 같다)
                keycap
                    .gesture(DragGesture(minimumDistance: 0).updating($holding) { _, state, _ in state = true })
                    .onChange(of: holding) { _, now in now ? startRepeating() : stopRepeating() }
                    .onDisappear { stopRepeating() }
            } else {
                keycap
                    .onTapGesture {
                        haptic.tapped()
                        tapFlash = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(120))
                            tapFlash = false
                        }
                        onPress(key)
                    }
                    .onLongPressGesture(minimumDuration: 10) {} onPressingChanged: { now in
                        pressed = now
                        if now { haptic.touched() }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPress(key) }
    }

    private var keycap: some View {
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
    }

    /// 닿자마자 한 번(heavy), 0.4초 뒤부터 0.08초마다 톡톡(rigid)
    private func startRepeating() {
        guard repeater == nil else { return }
        KeyHaptics.press()
        onPress(key)
        repeater = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            while !Task.isCancelled {
                KeyHaptics.tick()
                onPress(key)
                try? await Task.sleep(for: .seconds(0.08))
            }
        }
    }

    private func stopRepeating() {
        repeater?.cancel()
        repeater = nil
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
        case .symbol(let c):
            Text(String(c)).font(.system(size: side * 0.36, weight: .semibold, design: .monospaced)).foregroundStyle(DeckTheme.legend)
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
        case .symbol(let c): Self.symbolNames[c] ?? String(c)
        }
    }

    /// VoiceOver가 기호를 읽지 않고 넘어가는 경우가 있어 이름을 붙인다
    private static let symbolNames: [Character: String] = [
        "-": "빼기", "=": "등호", "\\": "역슬래시", "`": "백틱", "_": "밑줄", "+": "더하기", "|": "세로 막대", "~": "물결",
        "[": "왼쪽 대괄호", "]": "오른쪽 대괄호", "{": "왼쪽 중괄호", "}": "오른쪽 중괄호",
        ";": "세미콜론", "'": "작은따옴표", ":": "콜론", "\"": "큰따옴표",
    ]
}
