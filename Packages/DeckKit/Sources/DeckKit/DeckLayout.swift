import Foundation

/// 버튼을 눌렀을 때 맥이 할 일.
public enum ButtonAction: Codable, Equatable, Hashable, Sendable {
    case app(bundleId: String)
    /// keepOpen: 명령이 끝나도 창을 남길지. 서버(npm run dev 등)는 true, 금방 끝나는 명령은 false로 창이 닫힌다
    case command(command: String, directory: String?, keepOpen: Bool = true)
    case terminal(directory: String?)

    private enum CodingKeys: String, CodingKey {
        case kind, bundleId, command, directory, keepOpen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "app":
            self = .app(bundleId: try c.decode(String.self, forKey: .bundleId))
        case "command":
            // 이 값이 생기기 전에 저장된 버튼은 창 유지
            self = .command(command: try c.decode(String.self, forKey: .command),
                            directory: try c.decodeIfPresent(String.self, forKey: .directory),
                            keepOpen: try c.decodeIfPresent(Bool.self, forKey: .keepOpen) ?? true)
        case "terminal":
            self = .terminal(directory: try c.decodeIfPresent(String.self, forKey: .directory))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown kind \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundleId):
            try c.encode("app", forKey: .kind)
            try c.encode(bundleId, forKey: .bundleId)
        case .command(let command, let directory, let keepOpen):
            try c.encode("command", forKey: .kind)
            try c.encode(command, forKey: .command)
            try c.encodeIfPresent(directory, forKey: .directory)
            // 기본(창 유지)이면 적지 않는다. 예전 버튼과 저장 모양이 같게
            if !keepOpen { try c.encode(false, forKey: .keepOpen) }
        case .terminal(let directory):
            try c.encode("terminal", forKey: .kind)
            try c.encodeIfPresent(directory, forKey: .directory)
        }
    }
}

public struct DeckButton: Codable, Equatable, Hashable, Sendable {
    public var label: String
    public var action: ButtonAction

    public init(label: String, action: ButtonAction) {
        self.label = label
        self.action = action
    }
}

public struct DeckPage: Codable, Equatable, Hashable, Sendable {
    /// 항상 `DeckConstants.slotsPerPage`개. 빈 칸은 nil.
    public var buttons: [DeckButton?]

    public init(buttons: [DeckButton?] = Array(repeating: nil, count: DeckConstants.slotsPerPage)) {
        self.buttons = buttons
    }

    public var isEmpty: Bool { buttons.allSatisfy { $0 == nil } }
}

public enum LayoutError: Error, Equatable {
    case outOfRange
}

public struct DeckLayout: Codable, Equatable, Hashable, Sendable {
    public var pages: [DeckPage]

    public init(pages: [DeckPage]) {
        self.pages = pages
    }

    public static let empty = DeckLayout(pages: [DeckPage()])

    public mutating func set(_ button: DeckButton, page: Int, index: Int) throws {
        try checkRange(page: page, index: index)
        pages[page].buttons[index] = button
        normalize()
    }

    public mutating func clear(page: Int, index: Int) throws {
        try checkRange(page: page, index: index)
        pages[page].buttons[index] = nil
        normalize()
    }

    private func checkRange(page: Int, index: Int) throws {
        guard pages.indices.contains(page), (0..<DeckConstants.slotsPerPage).contains(index) else {
            throw LayoutError.outOfRange
        }
    }

    /// 끝에는 항상 빈 페이지가 정확히 하나 있다 (다음 버튼을 넣을 자리).
    /// 단, 버튼이 하나도 없으면 빈 페이지 하나만 남는다.
    private mutating func normalize() {
        while pages.count > 1, pages[pages.count - 1].isEmpty, pages[pages.count - 2].isEmpty {
            pages.removeLast()
        }
        if let last = pages.last, !last.isEmpty {
            pages.append(DeckPage())
        }
    }
}
