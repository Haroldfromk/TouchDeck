import DeckKit
import SwiftUI

/// 맥 홈 폴더 안을 눌러 가며 폴더를 고른다. 경로를 칠 필요가 없다.
struct FolderPickerView: View {
    let client: DeckClient
    let onPick: (String) -> Void

    @State private var path: String
    @Environment(\.dismiss) private var dismiss

    init(client: DeckClient, start: String, onPick: @escaping (String) -> Void) {
        self.client = client
        self.onPick = onPick
        _path = State(initialValue: start.isEmpty ? "~" : start)
    }

    private var listing: DeckClient.FolderListing? {
        client.folderListing?.path == path ? client.folderListing : nil
    }

    var body: some View {
        List {
            if let parent = FolderPath.parent(path) {
                Button {
                    path = parent
                } label: {
                    Label("위로", systemImage: "arrow.turn.left.up")
                }
            }
            Section(path) {
                if let listing {
                    if !listing.ok {
                        Text("이 폴더는 열 수 없어요").foregroundStyle(.secondary)
                    } else if listing.children.isEmpty {
                        Text("하위 폴더가 없어요").foregroundStyle(.secondary)
                    }
                    ForEach(listing.children, id: \.self) { name in
                        Button {
                            path = FolderPath.child(path, name)
                        } label: {
                            HStack {
                                Label(name, systemImage: "folder.fill").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    HStack { ProgressView(); Text("맥에서 폴더를 읽는 중").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle(path == "~" ? "홈 폴더" : String(path.split(separator: "/").last ?? "폴더"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("이 폴더 선택") {
                    onPick(path)
                    dismiss()
                }
            }
        }
        .task(id: path) { client.listFolder(path) }
    }
}
