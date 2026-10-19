import SwiftUI

/// 맥 메뉴바에 뜬 4자리 숫자를 입력해 이 기기를 허락받는다.
struct PairingView: View {
    let client: DeckClient
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(DeckTheme.terminal)
            VStack(spacing: 8) {
                Text("이 기기를 맥에 연결하기")
                    .font(.title2.weight(.semibold))
                Text("맥 메뉴바의 TouchDeck 아이콘을 누르면 4자리 숫자가 보여요.")
                    .foregroundStyle(DeckTheme.legendDim)
            }

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { i in
                    Text(digit(at: i))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .frame(width: 58, height: 70)
                        .background(DeckTheme.socket, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(i == code.count ? DeckTheme.terminal : .white.opacity(0.1), lineWidth: 2)
                        }
                }
            }
            .overlay {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .opacity(0.02)
                    .accessibilityLabel("페어링 숫자")
            }
            .onTapGesture { focused = true }

            if case .pairingFailed(_, let remaining) = client.phase {
                Text("숫자가 맞지 않아요. \(remaining)번 더 시도할 수 있어요.")
                    .foregroundStyle(DeckTheme.failure)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DeckTheme.body.ignoresSafeArea())
        .foregroundStyle(DeckTheme.legend)
        .onAppear { focused = true }
        .onChange(of: code) { _, new in
            let digits = String(new.filter(\.isNumber).prefix(4))
            if digits != new { code = digits; return }
            if digits.count == 4 {
                client.submitPairing(code: digits)
                code = ""
            }
        }
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }

    private func digit(at i: Int) -> String {
        let chars = Array(code)
        return i < chars.count ? String(chars[i]) : ""
    }
}
