import DeckKit
import SwiftUI

/// 키보드 볼륨 키처럼 생긴 키캡 세 개: 올림 / 음소거 / 내림.
/// 소리 크기 값은 맥이 알 때만(맥북 스피커 등) 막대로 보여준다. DisplayPort 모니터는 값을 모른다.
struct VolumeKeys: View {
    let client: DeckClient
    let vertical: Bool

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VolumeKeyCap(symbol: "speaker.plus.fill", label: "볼륨 올림", repeats: true) { client.pressVolumeKey(.up) }
            level
            VolumeKeyCap(symbol: client.muted ? "speaker.slash.fill" : "speaker.fill", label: "음소거",
                         lit: client.muted, repeats: false) { client.pressVolumeKey(.mute) }
            VolumeKeyCap(symbol: "speaker.minus.fill", label: "볼륨 내림", repeats: true) { client.pressVolumeKey(.down) }
        }
        .padding(10)
        .background(DeckTheme.socket, in: .rect(cornerRadius: 18))
        .opacity(client.volumeKeysAllowed ? 1 : 0.5)
    }

    /// 값을 알면 막대와 숫자, 모르면 비워 둔다 (키는 그래도 동작한다)
    @ViewBuilder
    private var level: some View {
        if client.volumeAvailable {
            GeometryReader { geo in
                let fraction = CGFloat(client.muted ? 0 : client.volume) / 100
                ZStack(alignment: vertical ? .bottom : .leading) {
                    Capsule().fill(DeckTheme.keyLip)
                    Capsule().fill(DeckTheme.volume)
                        .frame(width: vertical ? nil : geo.size.width * fraction,
                               height: vertical ? geo.size.height * fraction : nil)
                }
            }
            .frame(width: vertical ? 10 : nil, height: vertical ? nil : 10)
            .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
            .overlay(alignment: vertical ? .top : .trailing) {
                Text("\(client.volume)")
                    .font(.system(.caption, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(DeckTheme.legend)
                    .fixedSize()
                    .offset(x: vertical ? 0 : 30, y: vertical ? -20 : 0)
            }
            .padding(vertical ? .vertical : .horizontal, 24)
            .accessibilityElement()
            .accessibilityLabel("소리 크기")
            .accessibilityValue("\(client.volume)")
        } else {
            Spacer(minLength: 0)
        }
    }
}

/// 볼륨 키캡 하나. 누르는 동안 눌려 들어가고, repeats면 누르고 있는 동안 계속 보낸다.
struct VolumeKeyCap: View {
    let symbol: String
    let label: String
    var lit = false
    let repeats: Bool
    let action: () -> Void

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        let lip: CGFloat = 4
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12).fill(DeckTheme.keyLip).offset(y: lip)
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [DeckTheme.keycapTop, DeckTheme.keycap], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(lit ? DeckTheme.volume : DeckTheme.legend)
                }
                .offset(y: pressed ? lip : 0)
        }
        .frame(width: 56, height: 52)
        .padding(.bottom, lip)
        .animation(.spring(duration: 0.1), value: pressed)
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                action()
                guard repeats else { return }
                // 키보드처럼: 0.4초 누르고 있으면 그다음부터 0.12초마다 반복
                repeatTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    while !Task.isCancelled {
                        action()
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                }
            }
            .onEnded { _ in
                pressed = false
                repeatTask?.cancel()
                repeatTask = nil
            })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
