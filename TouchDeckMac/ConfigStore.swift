import DeckKit
import Foundation

/// 맥에만 있는 설정 원본: 버튼 배치와 허락한 기기.
struct DeckConfig: Codable, Equatable {
    var layout: DeckLayout
    var trustedDevices: [TrustedDevice]

    static let empty = DeckConfig(layout: .empty, trustedDevices: [])
}

final class ConfigStore {
    let url: URL

    init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/TouchDeck/config.json")
    }

    /// 파일이 없거나 깨졌으면 빈 설정으로 시작한다.
    func load() -> DeckConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(DeckConfig.self, from: data) else {
            return .empty
        }
        return config
    }

    func save(_ config: DeckConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
