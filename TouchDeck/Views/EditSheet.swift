import DeckKit
import SwiftUI

/// 버튼 추가/편집. 저장하면 맥에 보내고, 맥이 다시 보낸 배치로 화면이 바뀐다.
struct EditSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case app = "앱"
        case command = "명령어"
        case terminal = "새 터미널"
        var id: String { rawValue }
    }

    let client: DeckClient
    let target: EditTarget
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .app
    @State private var label = ""
    @State private var bundleId: String?
    @State private var command = ""
    @State private var directory = ""
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("종류", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                switch kind {
                case .app: appSection
                case .command: commandSection
                case .terminal: terminalSection
                }

                if target.button != nil {
                    Section {
                        Button("버튼 삭제", role: .destructive) {
                            client.clearButton(page: target.page, index: target.index)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(target.button == nil ? "버튼 추가" : "버튼 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        if let button = makeButton() {
                            client.setButton(button, page: target.page, index: target.index)
                        }
                        dismiss()
                    }
                    .disabled(makeButton() == nil)
                }
            }
        }
        .onAppear(perform: load)
        .preferredColorScheme(.dark)
    }

    // MARK: - 종류별 입력

    private var appSection: some View {
        Section("맥에 설치된 앱") {
            TextField("이름 (비우면 앱 이름)", text: $label)
            TextField("앱 검색", text: $search)
                .textInputAutocapitalization(.never)
            if client.apps.isEmpty {
                Text("맥에서 앱 목록을 받는 중이에요").foregroundStyle(.secondary)
            }
            ForEach(filteredApps, id: \.bundleId) { app in
                Button {
                    bundleId = app.bundleId
                } label: {
                    HStack(spacing: 12) {
                        if let icon = client.icons[app.bundleId] {
                            Image(uiImage: icon).resizable().frame(width: 32, height: 32)
                        }
                        Text(app.name).foregroundStyle(.primary)
                        Spacer()
                        if bundleId == app.bundleId {
                            Image(systemName: "checkmark").foregroundStyle(DeckTheme.app)
                        }
                    }
                }
            }
        }
    }

    private var commandSection: some View {
        Section {
            TextField("이름 (비우면 명령 그대로)", text: $label)
            TextField("명령 (예: blogrun)", text: $command)
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("실행할 폴더 (선택, 예: ~/Documents/Workspace/blog)", text: $directory)
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("맥에서 Alacritty 새 창이 열리고, 평소 쓰는 zsh에서 이 명령이 실행돼요. ~/.zshrc의 별칭도 그대로 쓸 수 있어요. 끝나도 창은 남아 있어요.")
        }
    }

    private var terminalSection: some View {
        Section {
            TextField("이름 (예: 새 터미널)", text: $label)
            TextField("시작 폴더 (선택)", text: $directory)
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } footer: {
            Text("Alacritty가 이미 켜져 있어도 빈 창이 하나 더 열려요.")
        }
    }

    private var filteredApps: [AppInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return client.apps }
        return client.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - 불러오기/만들기

    private func load() {
        guard let button = target.button else { return }
        label = button.label
        switch button.action {
        case .app(let id):
            kind = .app
            bundleId = id
        case .command(let cmd, let dir):
            kind = .command
            command = cmd
            directory = dir ?? ""
        case .terminal(let dir):
            kind = .terminal
            directory = dir ?? ""
        }
    }

    private func makeButton() -> DeckButton? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        let dir = directory.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .app:
            guard let bundleId else { return nil }
            let name = client.apps.first { $0.bundleId == bundleId }?.name ?? bundleId
            return DeckButton(label: trimmedLabel.isEmpty ? name : trimmedLabel, action: .app(bundleId: bundleId))
        case .command:
            let cmd = command.trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty else { return nil }
            return DeckButton(label: trimmedLabel.isEmpty ? cmd : trimmedLabel,
                              action: .command(command: cmd, directory: dir.isEmpty ? nil : dir))
        case .terminal:
            return DeckButton(label: trimmedLabel.isEmpty ? "새 터미널" : trimmedLabel,
                              action: .terminal(directory: dir.isEmpty ? nil : dir))
        }
    }
}
