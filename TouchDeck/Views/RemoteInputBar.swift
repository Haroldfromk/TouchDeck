import DeckKit
import SwiftUI

/// 맥 화면 보기 아래의 입력칸. 다 쓰고 한 번에 보낸다(한글 조합이 맥에서 겹쳐 찍히지 않게).
/// 위 줄의 특수 키는 누르면 바로 맥에 간다. 친 글은 어디에도 남기지 않는다.
struct RemoteInputBar: View {
    let client: DeckClient
    @State private var text = ""
    @AppStorage("screen.sendEnter") private var sendEnter = true
    @FocusState private var focused: Bool

    private struct KeyItem {
        let key: RemoteKey
        let label: String
        let spoken: String
    }

    private static let keys: [KeyItem] = [
        KeyItem(key: .escape, label: "esc", spoken: "이스케이프"),
        KeyItem(key: .tab, label: "tab", spoken: "탭"),
        KeyItem(key: .shiftTab, label: "⇧tab", spoken: "시프트 탭"),
        KeyItem(key: .up, label: "↑", spoken: "위"),
        KeyItem(key: .down, label: "↓", spoken: "아래"),
        KeyItem(key: .left, label: "←", spoken: "왼쪽"),
        KeyItem(key: .right, label: "→", spoken: "오른쪽"),
        KeyItem(key: .delete, label: "⌫", spoken: "지우기"),
        KeyItem(key: .controlC, label: "⌃C", spoken: "컨트롤 C"),
        KeyItem(key: .enter, label: "⏎", spoken: "엔터"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.keys, id: \.key) { item in
                        Button { client.pressKey(item.key) } label: {
                            Text(item.label)
                                .font(.callout.weight(.semibold).monospaced())
                                .frame(minWidth: 44, minHeight: 36)
                                .padding(.horizontal, 6)
                                .background(DeckTheme.socket, in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DeckTheme.legend)
                        .accessibilityLabel(item.spoken)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("맥에 보낼 글", text: $text)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(DeckTheme.socket, in: .rect(cornerRadius: 10))
                    .foregroundStyle(DeckTheme.legend)
                    .onChange(of: text) { _, new in
                        if new.count > TextInput.maxCharacters { text = String(new.prefix(TextInput.maxCharacters)) }
                    }
                Toggle("보내고 엔터", isOn: $sendEnter)
                    .fixedSize()
                    .font(.callout)
                    .foregroundStyle(DeckTheme.legendDim)
                    .tint(DeckTheme.legend)
                Button("보내기", action: send)
                    .font(.callout.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(DeckTheme.terminal)
            }
        }
        .padding(10)
        .background(DeckTheme.keycap)
        .onAppear { focused = true }
    }

    /// 빈 입력칸이면 "보내고 엔터"일 때 엔터만 간다
    private func send() {
        client.typeText(text, thenEnter: sendEnter)
        text = ""
        focused = true
    }
}
