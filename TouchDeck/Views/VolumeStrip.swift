import DeckKit
import SwiftUI

/// 위아래(아이폰은 좌우)로 끄는 볼륨 띠와 음소거 키.
/// 볼륨 키 신호는 "한 칸 올려/내려"만 할 수 있어서, 끈 거리만큼 키를 대신 누른다.
/// 손을 떼면 손잡이는 가운데로 돌아온다. macOS가 값을 알면(맥북 스피커 등) 띠 안에 지금 값을 채워 보여준다.
struct VolumeStrip: View {
    let client: DeckClient
    let vertical: Bool

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            DragStrip(vertical: vertical, level: client.volumeAvailable ? (client.muted ? 0 : client.volume) : nil,
                      onKey: client.pressVolumeKey)
            VolumeKeyCap(symbol: client.muted ? "speaker.slash.fill" : "speaker.fill", label: "음소거", lit: client.muted) {
                client.pressVolumeKey(.mute)
            }
        }
        .padding(10)
        .background(DeckTheme.socket, in: .rect(cornerRadius: 18))
        .opacity(client.volumeKeysAllowed ? 1 : 0.5)
    }
}

private struct DragStrip: View {
    let vertical: Bool
    /// 0~100. 맥이 값을 모르면 nil
    let level: Int?
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
                if let level {
                    // 지금 값: 아래(아이폰은 왼쪽)부터 채운다
                    Capsule().fill(DeckTheme.volume.opacity(0.55))
                        .frame(width: vertical ? nil : length * CGFloat(level) / 100,
                               height: vertical ? length * CGFloat(level) / 100 : nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
                }
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
        .accessibilityValue(level.map { "\($0)" } ?? "값 모름")
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
        .onTapGesture(perform: action)
        .onLongPressGesture(minimumDuration: 10) {} onPressingChanged: { pressed = $0 }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
