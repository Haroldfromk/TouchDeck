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
    @State private var closeWhenDone = false
    @State private var search = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("종류", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // 앱을 고를 때는 검색창을 목록 밖 맨 위에 고정한다. 목록을 내려도 사라지지 않게
                if kind == .app {
                    AppSearchField(text: $search, onSubmit: selectIfSingleResult)
                        .padding(.horizontal)
                }

                form
            }
            .padding(.top, 8)
            .background(Color(uiColor: .systemGroupedBackground))
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
        // 검색창은 직접 누를 때만 커서가 간다. 열자마자 키보드가 올라와 목록을 가리지 않게
        .onAppear(perform: load)
        .preferredColorScheme(.dark)
    }

    private var form: some View {
        Form {
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
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 종류별 입력

    @ViewBuilder
    private var appSection: some View {
        Section("버튼 이름") {
            TextField("비우면 앱 이름 그대로", text: $label)
        }
        Section {
            if client.apps.isEmpty {
                Text("맥에서 앱 목록을 받는 중이에요").foregroundStyle(.secondary)
            } else if filteredApps.isEmpty {
                Text("‘\(search)’와 맞는 앱이 없어요").foregroundStyle(.secondary)
            }
            ForEach(filteredApps, id: \.bundleId) { app in
                Button {
                    bundleId = app.bundleId
                } label: {
                    HStack(spacing: 12) {
                        if let icon = client.icons[app.bundleId] {
                            Image(uiImage: icon).resizable().frame(width: 32, height: 32)
                        }
                        Text(highlighted(app.name)).foregroundStyle(.primary)
                        Spacer()
                        if bundleId == app.bundleId {
                            Image(systemName: "checkmark").foregroundStyle(DeckTheme.app)
                        }
                    }
                }
                .accessibilityLabel(app.name)
            }
        } header: {
            Text(search.isEmpty ? "맥에 설치된 앱 \(client.apps.count)개" : "검색 결과 \(filteredApps.count)개")
        }
    }

    /// 검색어와 글자 그대로 맞는 부분을 굵게
    private func highlighted(_ name: String) -> AttributedString {
        var text = AttributedString(name)
        if let range = AppSearch.matchRange(in: name, query: search),
           let lower = AttributedString.Index(range.lowerBound, within: text),
           let upper = AttributedString.Index(range.upperBound, within: text) {
            text[lower..<upper].font = .body.bold()
            text[lower..<upper].foregroundColor = DeckTheme.app
        }
        return text
    }

    /// 검색 결과가 하나뿐이면 엔터만 쳐도 그 앱을 고른다
    private func selectIfSingleResult() {
        if filteredApps.count == 1 { bundleId = filteredApps[0].bundleId }
    }

    private var commandSection: some View {
        Section {
            TextField("이름 (비우면 명령 그대로)", text: $label)
            TextField("명령 (예: blogrun)", text: $command)
                .font(.body.monospaced())
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            folderField("실행할 폴더 (비우면 홈 폴더)")
            Toggle("명령이 끝나면 창 닫기", isOn: $closeWhenDone)
        } footer: {
            Text(closeWhenDone
                 ? "맥에서 Alacritty 새 창이 열리고 이 명령이 실행돼요. 끝나면 창이 저절로 닫혀요. 오류가 나도 바로 닫히니, 결과를 봐야 하는 명령은 끄세요."
                 : "맥에서 Alacritty 새 창이 열리고, 평소 쓰는 zsh에서 이 명령이 실행돼요. ~/.zshrc의 별칭도 그대로 쓸 수 있어요. 끝나도 창이 남아서 서버(npm run dev 등)를 띄워 두기 좋아요.")
        }
    }

    private var terminalSection: some View {
        Section {
            TextField("이름 (예: 새 터미널)", text: $label)
            folderField("시작 폴더 (비우면 홈 폴더)")
        } footer: {
            Text("Alacritty가 이미 켜져 있어도 빈 창이 하나 더 열려요.")
        }
    }

    /// 맥 폴더 경로. 직접 칠 수도 있고, 폴더 고르기로 맥의 폴더를 눌러 가며 고를 수도 있다
    @ViewBuilder
    private func folderField(_ placeholder: String) -> some View {
        TextField(placeholder, text: $directory)
            .font(.body.monospaced())
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        NavigationLink {
            FolderPickerView(client: client, start: FolderPath.isInsideHome(directory) ? directory : "~") { directory = $0 }
        } label: {
            Label("맥에서 폴더 고르기", systemImage: "folder")
        }
    }

    private var filteredApps: [AppInfo] {
        AppSearch.filter(client.apps, query: search)
    }

    // MARK: - 불러오기/만들기

    private func load() {
        guard let button = target.button else { return }
        label = button.label
        switch button.action {
        case .app(let id):
            kind = .app
            bundleId = id
        case .command(let cmd, let dir, let keepOpen):
            kind = .command
            command = cmd
            directory = dir ?? ""
            closeWhenDone = !keepOpen
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
                              action: .command(command: cmd, directory: dir.isEmpty ? nil : dir, keepOpen: !closeWhenDone))
        case .terminal:
            return DeckButton(label: trimmedLabel.isEmpty ? "새 터미널" : trimmedLabel,
                              action: .terminal(directory: dir.isEmpty ? nil : dir))
        }
    }
}
