import DeckKit
import SwiftUI

/// 맥 화면 보기 아래의 입력칸. 다 쓰고 한 번에 보낸다(한글 조합이 맥에서 겹쳐 찍히지 않게).
/// 위 줄의 특수 키는 누르면 바로 맥에 간다. 친 글은 어디에도 남기지 않는다.
struct RemoteInputBar: View {
    let client: DeckClient
    @State private var text = ""
    @AppStorage("screen.sendEnter") private var sendEnter = true
    @FocusState private var focused: Bool

    fileprivate struct KeyItem {
        let key: RemoteKey
        let label: String
        let spoken: String
        /// 길게 누르면 뗄 때까지 계속 보낸다 (⌫)
        var repeats = false
        /// 글자 대신 크게 그릴 아이콘. "⌫" 글자는 작아서 잘 안 보인다
        var symbol: String?
    }

    private static let keys: [KeyItem] = [
        KeyItem(key: .escape, label: "esc", spoken: "이스케이프"),
        KeyItem(key: .tab, label: "tab", spoken: "탭"),
        KeyItem(key: .shiftTab, label: "⇧tab", spoken: "시프트 탭"),
        KeyItem(key: .up, label: "↑", spoken: "위"),
        KeyItem(key: .down, label: "↓", spoken: "아래"),
        KeyItem(key: .left, label: "←", spoken: "왼쪽"),
        KeyItem(key: .right, label: "→", spoken: "오른쪽"),
        KeyItem(key: .selectAll, label: "⌘A", spoken: "전체 선택"),
        KeyItem(key: .delete, label: "⌫", spoken: "지우기", repeats: true, symbol: "delete.left.fill"),
        KeyItem(key: .controlC, label: "⌃C", spoken: "컨트롤 C"),
        KeyItem(key: .enter, label: "⏎", spoken: "엔터"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.keys, id: \.key) { item in
                        KeyButton(item: item) { client.pressKey(item.key) }
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
                Button(action: send) {
                    Text("보내기")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(DeckTheme.terminal, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(KeyPressStyle())
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

/// 특수 키 버튼 하나. ⌫는 맥 키보드처럼 0.4초 누르고 있으면 뗄 때까지 연달아 지운다
private struct KeyButton: View {
    let item: RemoteInputBar.KeyItem
    let send: () -> Void
    /// 누르는 중. 손을 떼거나 스크롤에 손가락을 뺏기면 저절로 false가 돼서, 지우기가 멈추지 않는 일이 없다
    @GestureState private var pressing = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        if item.repeats {
            label
                .gesture(DragGesture(minimumDistance: 0).updating($pressing) { _, state, _ in state = true })
                .onChange(of: pressing) { _, now in now ? startRepeating() : stopRepeating() }
                .onDisappear { stopRepeating() }
                .accessibilityLabel(item.spoken)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { send() }
        } else {
            Button(action: send) { label }
                .buttonStyle(KeyPressStyle())
                .accessibilityLabel(item.spoken)
        }
    }

    private var label: some View {
        Group {
            if let symbol = item.symbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 60)
            } else {
                Text(item.label)
                    .font(.callout.weight(.semibold).monospaced())
            }
        }
        .frame(minWidth: 44, minHeight: 36)
        .padding(.horizontal, 6)
        .background(DeckTheme.socket.opacity(pressing ? 0.6 : 1), in: .rect(cornerRadius: 8))
        .foregroundStyle(DeckTheme.legend)
        .contentShape(.rect)
    }

    /// 누르자마자 한 번, 0.4초 뒤부터 0.08초마다
    private func startRepeating() {
        guard repeater == nil else { return }
        KeyHaptics.press()
        send()
        repeater = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            while !Task.isCancelled {
                KeyHaptics.tick()
                send()
                try? await Task.sleep(for: .seconds(0.08))
            }
        }
    }

    private func stopRepeating() {
        repeater?.cancel()
        repeater = nil
    }
}
