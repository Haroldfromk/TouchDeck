import DeckKit
import SwiftUI

/// 키캡 하나. 탭하면 맥에서 실행, 길게 눌렀다 떼면 편집, 길게 누른 채 끌면 옮기기.
struct ButtonTile: View {
    let button: DeckButton?
    let icon: UIImage?
    let failed: Bool
    /// 맥이 "실행했음"을 돌려준 직후 잠깐 true. 테두리가 버튼 종류 색으로 빛난다
    var succeeded = false
    /// 옮기기 모드. 버튼이 흔들리고, 탭하면 실행 대신 편집 창
    var arranging = false
    /// 흔들림 시작 시점을 칸마다 조금씩 어긋나게
    var phase: Double = 0
    /// 끌려 나간 칸. 버튼은 손가락을 따라가고 이 칸은 빈 칸처럼 보인다
    var lifted = false
    /// 끄는 버튼이 놓일 칸
    var highlighted = false
    /// 맥이 옮기기를 알 때만 끌 수 있다. 아니면 길게 눌렀다 떼는 것처럼 편집 창
    var canDrag = false
    /// 10pt 넘게 끈 뒤부터 손가락 위치(DeckView.gridSpace 좌표). 둘째 값은 이번 끌기의 첫 신호인지
    var onDragChanged: (CGPoint, Bool) -> Void = { _, _ in }
    /// 끌던 손을 뗐을 때. 위치를 모르면 nil
    var onDragEnded: (CGPoint?) -> Void = { _ in }
    let onTap: () -> Void
    let onEdit: () -> Void

    @State private var pressed = false
    /// 짧게 탭하면 "누르고 있는 동안" 신호가 오기 전에 손이 떨어진다. 그래도 눌림이 보이게 잠깐 켠다
    @State private var tapFlash = false
    @State private var haptic = PressHaptic()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 길게 누르기가 끝나 끌기를 기다리거나 끄는 중
    @GestureState private var holding = false
    @State private var dragStarted = false
    @State private var longFired = false
    @State private var endHandled = false
    /// 옮기기 모드면 길게 누르지 않고 바로 끈다. 끄는 도중 옮기기 모드가 켜져도 손짓이 바뀌지 않게, 손을 뗐을 때만 따라 바꾼다
    @State private var quickDrag = false
    private var down: Bool { pressed || tapFlash }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if let button, !lifted {
                    keycap(button, side: side)
                } else {
                    socket(side: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .modifier(Wiggle(on: arranging && button != nil && !lifted && !reduceMotion, phase: phase))
        }
        .contentShape(.rect)
        .onTapGesture {
            flashPress()
            button == nil || arranging ? onEdit() : onTap()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // 버튼은 떼는 순간 정한다(움직이지 않았으면 편집, 끌었으면 옮기기). 빈 칸은 바로 편집
            if button == nil { onEdit() } else { longFired = true }
        } onPressingChanged: { now in
            pressed = now
            if now { haptic.touched() }
        }
        .simultaneousGesture(pressDrag, including: button == nil ? .subviews : .all)
        .onAppear { quickDrag = arranging }
        .onChange(of: arranging) { _, now in
            if !holding { quickDrag = now }
        }
        .onChange(of: holding) { _, now in
            guard !now else { return }
            quickDrag = arranging
            // 손을 뗐는데 끝 신호가 오지 않는 경우를 대비한다
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                if !endHandled { finish(at: nil) }
                endHandled = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(button?.label ?? "빈 칸")
        .accessibilityHint(button == nil ? "버튼 추가" : "맥에서 실행")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "편집", onEdit)
    }

    /// 길게 누른 뒤(옮기기 모드면 바로) 끌기. 10pt 넘게 움직이면 옮기기가 시작된다
    private var pressDrag: some Gesture {
        LongPressGesture(minimumDuration: quickDrag ? 0.01 : 0.45)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(DeckView.gridSpace)))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if !dragStarted, canDrag, hypot(drag.translation.width, drag.translation.height) >= 10 {
                    dragStarted = true
                    onDragChanged(drag.location, true)
                } else if dragStarted {
                    onDragChanged(drag.location, false)
                }
            }
            .onEnded { value in
                endHandled = true
                if case .second(true, let drag?) = value { finish(at: drag.location) } else { finish(at: nil) }
            }
    }

    private func finish(at location: CGPoint?) {
        defer { longFired = false }
        if dragStarted {
            dragStarted = false
            onDragEnded(location)
        } else if longFired {
            // 길게 눌렀다 움직이지 않고 뗐다. 옮기기 모드에서 짧게 탭한 건 onTapGesture가 맡는다
            onEdit()
        }
    }

    /// 0.12초 동안 확실히 눌렸다 올라온다. 아이패드는 진동이 없어서 화면으로 보여줘야 한다
    private func flashPress() {
        haptic.tapped()
        tapFlash = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            tapFlash = false
        }
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
                // 눌리는 동안 윗면이 살짝 밝아진다
                .overlay {
                    RoundedRectangle(cornerRadius: radius).fill(.white.opacity(down ? 0.09 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(borderColor(button), lineWidth: failed || succeeded || highlighted ? 3 : (arrangeOutline ? 2 : 1))
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(DeckTheme.accent(for: button.action))
                        .frame(width: side * 0.07, height: side * 0.07)
                        .scaleEffect(down ? 1.35 : 1)
                        .shadow(color: DeckTheme.accent(for: button.action), radius: down || succeeded ? 9 : 3)
                        .padding(side * 0.1)
                }
                .overlay { legend(button, side: side) }
                .offset(y: down ? lip : 0)
        }
        .padding(.bottom, lip)
        .animation(.spring(duration: 0.12), value: down)
        .animation(.easeOut(duration: 0.25), value: succeeded)
    }

    private func borderColor(_ button: DeckButton) -> Color {
        if failed { return DeckTheme.failure }
        if succeeded { return DeckTheme.accent(for: button.action) }
        if highlighted || arrangeOutline { return DeckTheme.legend.opacity(highlighted ? 0.9 : 0.5) }
        return .white.opacity(0.06)
    }

    /// 동작 줄이기를 켜면 흔드는 대신 테두리로 옮기기 모드임을 알린다
    private var arrangeOutline: Bool { arranging && reduceMotion }

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
                    .strokeBorder(style: StrokeStyle(lineWidth: highlighted ? 2.5 : 1.5, dash: [5, 5]))
                    .foregroundStyle(.white.opacity(highlighted ? 0.8 : (down ? 0.35 : 0.15)))
            }
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: side * 0.16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.bottom, side * 0.06)
    }
}

/// 옮기기 모드에서 iOS 홈 화면처럼 좌우로 살짝 기울며 흔들린다. 왕복 0.25초, ±1.5도
private struct Wiggle: ViewModifier {
    let on: Bool
    let phase: Double

    func body(content: Content) -> some View {
        if on {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                content.rotationEffect(.degrees(1.5 * sin((t / 0.25 + phase) * 2 * .pi)))
            }
        } else {
            content
        }
    }
}
