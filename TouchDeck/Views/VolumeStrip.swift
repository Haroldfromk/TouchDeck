import DeckKit
import SwiftUI

/// 볼륨 게이지와 음소거 키.
/// 맥이 실제 값을 알면(macOS가 아는 장치, 또는 BetterDisplay가 켜진 모니터) 값만큼 차오르는 게이지로 값을 정한다.
/// 모르면 끄는 띠로 볼륨 키 신호를 보낸다 (한 칸씩만 올리고 내릴 수 있다).
struct VolumeStrip: View {
    let client: DeckClient
    let vertical: Bool

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            if client.volumeAvailable {
                VolumeGauge(vertical: vertical, value: client.volume, muted: client.muted, onChange: client.setVolume)
            } else {
                DragStrip(vertical: vertical, onKey: client.pressVolumeKey)
            }
            VolumeKeyCap(symbol: client.muted ? "speaker.slash.fill" : "speaker.fill", label: "음소거", lit: client.muted) {
                client.pressVolumeKey(.mute)
            }
        }
        .padding(10)
        .background(DeckTheme.socket, in: .rect(cornerRadius: 18))
        .opacity(client.volumeKeysAllowed ? 1 : 0.5)
    }
}

/// 실제 소리 크기만큼 차오르는 게이지. 누르거나 끈 위치가 곧 값이다.
private struct VolumeGauge: View {
    let vertical: Bool
    let value: Int
    let muted: Bool
    let onChange: (Int) -> Void

    @State private var lastHapticValue = -1
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            let fraction = CGFloat(value) / 100
            ZStack(alignment: vertical ? .bottom : .leading) {
                RoundedRectangle(cornerRadius: 14).fill(DeckTheme.keyLip)
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [DeckTheme.volume, DeckTheme.volume.opacity(0.6)],
                                         startPoint: vertical ? .top : .trailing, endPoint: vertical ? .bottom : .leading))
                    .opacity(muted ? 0.3 : 1)
                    .frame(width: vertical ? nil : length * fraction, height: vertical ? length * fraction : nil)
                    .animation(.easeOut(duration: 0.15), value: value)
                // 10% 눈금
                ForEach(1..<10, id: \.self) { i in
                    Rectangle().fill(.white.opacity(0.08))
                        .frame(width: vertical ? nil : 1, height: vertical ? 1 : nil)
                        .offset(x: vertical ? 0 : length * CGFloat(i) / 10, y: vertical ? -length * CGFloat(i) / 10 : 0)
                }
                Text(muted ? "음소거" : "\(value)")
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.bold))
                    .foregroundStyle(DeckTheme.legend)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .top : .trailing)
                    .padding(vertical ? .top : .trailing, 10)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let position = vertical ? length - drag.location.y : drag.location.x
                let next = Int((min(max(position / length, 0), 1) * 100).rounded())
                guard next != value else { return }
                onChange(next)
                // 10% 눈금을 넘을 때마다 짧게 진동
                if next / 10 != lastHapticValue / 10 { haptic.impactOccurred() }
                lastHapticValue = next
            })
        }
        .frame(width: vertical ? 56 : nil, height: vertical ? nil : 56)
        .accessibilityElement()
        .accessibilityLabel("소리 크기")
        .accessibilityValue(muted ? "음소거" : "\(value)")
        .accessibilityAdjustableAction { direction in
            onChange(min(max(value + (direction == .increment ? 5 : -5), 0), 100))
        }
    }
}

private struct DragStrip: View {
    let vertical: Bool
    let onKey: (VolumeKey) -> Void

    @State private var drag = VolumeDrag(step: 16)
    @State private var offset: CGFloat = 0
    private let knob: CGFloat = 30
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            let travel = max(length / 2 - knob / 2 - 4, 0)
            ZStack {
                Capsule().fill(DeckTheme.keyLip)
                // 끄는 방향 안내
                Image(systemName: vertical ? "chevron.up" : "chevron.right")
                    .font(.caption.weight(.bold)).foregroundStyle(DeckTheme.legendDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .top : .trailing)
                    .padding(10)
                Image(systemName: vertical ? "chevron.down" : "chevron.left")
                    .font(.caption.weight(.bold)).foregroundStyle(DeckTheme.legendDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
                    .padding(10)
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [DeckTheme.keycapTop, DeckTheme.keycap], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().fill(DeckTheme.volume).frame(width: vertical ? 26 : 3, height: vertical ? 3 : 26))
                    .frame(width: vertical ? 48 : knob, height: vertical ? knob : 48)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                    .offset(x: vertical ? 0 : offset, y: vertical ? -offset : 0)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // 올림 쪽이 +: 세로는 위로, 가로는 오른쪽으로
                    let distance = vertical ? -value.translation.height : value.translation.width
                    offset = min(max(distance, -travel), travel)
                    for key in drag.update(distance: distance) {
                        onKey(key)
                        haptic.impactOccurred()
                    }
                }
                .onEnded { _ in
                    drag.end()
                    withAnimation(.spring(duration: 0.25)) { offset = 0 }
                })
        }
        .frame(width: vertical ? 56 : nil, height: vertical ? nil : 56)
        .accessibilityElement()
        .accessibilityLabel("소리 크기")
        .accessibilityValue("값 모름")
        .accessibilityAdjustableAction { direction in
            onKey(direction == .increment ? .up : .down)
        }
    }
}

/// 음소거 키캡. 누르는 동안 눌려 들어간다.
struct VolumeKeyCap: View {
    let symbol: String
    let label: String
    var lit = false
    let action: () -> Void

    @State private var pressed = false
    @State private var tapFlash = false
    @State private var haptic = PressHaptic()
    private var down: Bool { pressed || tapFlash }

    var body: some View {
        let lip: CGFloat = 4
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12).fill(DeckTheme.keyLip).offset(y: lip)
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [DeckTheme.keycapTop, DeckTheme.keycap], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                .overlay { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(down ? 0.09 : 0)) }
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(lit ? DeckTheme.volume : DeckTheme.legend)
                }
                .offset(y: down ? lip : 0)
        }
        .frame(width: 56, height: 52)
        .padding(.bottom, lip)
        .animation(.spring(duration: 0.1), value: down)
        .contentShape(.rect)
        .onTapGesture {
            haptic.tapped()
            tapFlash = true
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                tapFlash = false
            }
            action()
        }
        .onLongPressGesture(minimumDuration: 10) {} onPressingChanged: { now in
            pressed = now
            if now { haptic.touched() }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
