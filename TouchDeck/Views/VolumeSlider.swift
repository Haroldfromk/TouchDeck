import SwiftUI

/// 믹서 페이더처럼 홈이 파인 볼륨 조절기. 가로 배치에선 세로로, 세로 배치에선 가로로 눕는다.
struct VolumeSlider: View {
    let value: Int
    let available: Bool
    let vertical: Bool
    let onChange: (Int) -> Void
    let onToggleMute: () -> Void

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Button(action: onToggleMute) {
                Image(systemName: speakerSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(DeckTheme.legend)
            .disabled(!available)
            .accessibilityLabel(value == 0 ? "음소거 해제" : "음소거")

            if available {
                fader
            } else {
                Text("지금 출력 장치는 맥에서 소리 크기를 바꿀 수 없어요")
                    .font(.footnote)
                    .foregroundStyle(DeckTheme.legendDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Text(available ? "\(value)" : "–")
                .font(.system(.callout, design: .rounded).monospacedDigit().weight(.semibold))
                .foregroundStyle(DeckTheme.legend)
                .frame(minWidth: 36)
        }
        .padding(vertical ? .vertical : .horizontal, 14)
        .padding(vertical ? .horizontal : .vertical, 8)
        .background(DeckTheme.socket, in: .rect(cornerRadius: 18))
    }

    private var speakerSymbol: String {
        if !available { return "speaker.slash" }
        if value == 0 { return "speaker.slash.fill" }
        return value < 34 ? "speaker.wave.1.fill" : value < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    private var fader: some View {
        GeometryReader { geo in
            let length = vertical ? geo.size.height : geo.size.width
            let knob: CGFloat = 26
            let travel = max(length - knob, 1)
            let offset = travel * CGFloat(value) / 100
            ZStack(alignment: vertical ? .bottom : .leading) {
                // 홈
                Capsule()
                    .fill(DeckTheme.keyLip)
                    .frame(width: vertical ? 10 : nil, height: vertical ? nil : 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 채워진 부분
                Capsule()
                    .fill(DeckTheme.volume)
                    .frame(width: vertical ? 10 : offset + knob / 2, height: vertical ? offset + knob / 2 : 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
                // 손잡이
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [DeckTheme.keycapTop, DeckTheme.keycap], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().fill(DeckTheme.legend.opacity(0.7)).frame(width: vertical ? 22 : 2, height: vertical ? 2 : 22))
                    .frame(width: vertical ? 44 : knob, height: vertical ? knob : 44)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                    .offset(x: vertical ? 0 : offset, y: vertical ? -offset : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let position = vertical ? length - drag.location.y : drag.location.x
                let fraction = (position - knob / 2) / travel
                onChange(Int((min(max(fraction, 0), 1) * 100).rounded()))
            })
        }
        .accessibilityElement()
        .accessibilityLabel("소리 크기")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            onChange(min(max(value + (direction == .increment ? 5 : -5), 0), 100))
        }
    }
}
