import Foundation

/// 맥에 설치된 앱 하나. `icon`은 PNG를 base64 글자로 바꾼 것.
public struct AppInfo: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var bundleId: String
    public var icon: String

    public init(name: String, bundleId: String, icon: String) {
        self.name = name
        self.bundleId = bundleId
        self.icon = icon
    }
}

/// 기기(아이패드, 아이폰, 나중에 ESP32) → 맥
public enum ClientMessage: Equatable, Sendable {
    case hello(deviceId: String, deviceName: String)
    case pair(code: String)
    case auth(signature: String)
    case press(page: Int, index: Int)
    case getApps
    case setButton(page: Int, index: Int, button: DeckButton)
    case clearButton(page: Int, index: Int)
    case setVolume(Int)
}

/// 맥 → 기기
public enum ServerMessage: Equatable, Sendable {
    case needPairing
    case pairingFailed(remaining: Int)
    case paired(token: String)
    case challenge(nonce: String)
    case authorized
    case unauthorized
    case layout(DeckLayout)
    case apps([AppInfo])
    case pressResult(page: Int, index: Int, ok: Bool, message: String?)
    case volume(value: Int, muted: Bool)
}

/// 모든 메시지가 쓰는 JSON 키. 최상위 `type`으로 종류를 나눈다.
private enum Key: String, CodingKey {
    case type, deviceId, deviceName, code, signature, page, index, button, value
    case remaining, token, nonce, pages, items, ok, message, muted
}

extension ClientMessage: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hello":
            self = .hello(deviceId: try c.decode(String.self, forKey: .deviceId),
                          deviceName: try c.decode(String.self, forKey: .deviceName))
        case "pair": self = .pair(code: try c.decode(String.self, forKey: .code))
        case "auth": self = .auth(signature: try c.decode(String.self, forKey: .signature))
        case "press":
            self = .press(page: try c.decode(Int.self, forKey: .page), index: try c.decode(Int.self, forKey: .index))
        case "getApps": self = .getApps
        case "setButton":
            self = .setButton(page: try c.decode(Int.self, forKey: .page),
                              index: try c.decode(Int.self, forKey: .index),
                              button: try c.decode(DeckButton.self, forKey: .button))
        case "clearButton":
            self = .clearButton(page: try c.decode(Int.self, forKey: .page), index: try c.decode(Int.self, forKey: .index))
        case "setVolume": self = .setVolume(try c.decode(Int.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .hello(let deviceId, let deviceName):
            try c.encode("hello", forKey: .type)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(deviceName, forKey: .deviceName)
        case .pair(let code):
            try c.encode("pair", forKey: .type)
            try c.encode(code, forKey: .code)
        case .auth(let signature):
            try c.encode("auth", forKey: .type)
            try c.encode(signature, forKey: .signature)
        case .press(let page, let index):
            try c.encode("press", forKey: .type)
            try c.encode(page, forKey: .page)
            try c.encode(index, forKey: .index)
        case .getApps:
            try c.encode("getApps", forKey: .type)
        case .setButton(let page, let index, let button):
            try c.encode("setButton", forKey: .type)
            try c.encode(page, forKey: .page)
            try c.encode(index, forKey: .index)
            try c.encode(button, forKey: .button)
        case .clearButton(let page, let index):
            try c.encode("clearButton", forKey: .type)
            try c.encode(page, forKey: .page)
            try c.encode(index, forKey: .index)
        case .setVolume(let value):
            try c.encode("setVolume", forKey: .type)
            try c.encode(value, forKey: .value)
        }
    }
}

extension ServerMessage: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "needPairing": self = .needPairing
        case "pairingFailed": self = .pairingFailed(remaining: try c.decode(Int.self, forKey: .remaining))
        case "paired": self = .paired(token: try c.decode(String.self, forKey: .token))
        case "challenge": self = .challenge(nonce: try c.decode(String.self, forKey: .nonce))
        case "authorized": self = .authorized
        case "unauthorized": self = .unauthorized
        case "layout": self = .layout(DeckLayout(pages: try c.decode([DeckPage].self, forKey: .pages)))
        case "apps": self = .apps(try c.decode([AppInfo].self, forKey: .items))
        case "pressResult":
            self = .pressResult(page: try c.decode(Int.self, forKey: .page),
                                index: try c.decode(Int.self, forKey: .index),
                                ok: try c.decode(Bool.self, forKey: .ok),
                                message: try c.decodeIfPresent(String.self, forKey: .message))
        case "volume":
            self = .volume(value: try c.decode(Int.self, forKey: .value), muted: try c.decode(Bool.self, forKey: .muted))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .needPairing:
            try c.encode("needPairing", forKey: .type)
        case .pairingFailed(let remaining):
            try c.encode("pairingFailed", forKey: .type)
            try c.encode(remaining, forKey: .remaining)
        case .paired(let token):
            try c.encode("paired", forKey: .type)
            try c.encode(token, forKey: .token)
        case .challenge(let nonce):
            try c.encode("challenge", forKey: .type)
            try c.encode(nonce, forKey: .nonce)
        case .authorized:
            try c.encode("authorized", forKey: .type)
        case .unauthorized:
            try c.encode("unauthorized", forKey: .type)
        case .layout(let layout):
            try c.encode("layout", forKey: .type)
            try c.encode(layout.pages, forKey: .pages)
        case .apps(let items):
            try c.encode("apps", forKey: .type)
            try c.encode(items, forKey: .items)
        case .pressResult(let page, let index, let ok, let message):
            try c.encode("pressResult", forKey: .type)
            try c.encode(page, forKey: .page)
            try c.encode(index, forKey: .index)
            try c.encode(ok, forKey: .ok)
            try c.encodeIfPresent(message, forKey: .message)
        case .volume(let value, let muted):
            try c.encode("volume", forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encode(muted, forKey: .muted)
        }
    }
}

public enum MessageCodingError: Error {
    case notUTF8
}

extension ClientMessage {
    public func encoded() throws -> String { try encodeToText(self) }
    public static func decode(_ text: String) throws -> ClientMessage { try decodeFromText(text) }
}

extension ServerMessage {
    public func encoded() throws -> String { try encodeToText(self) }
    public static func decode(_ text: String) throws -> ServerMessage { try decodeFromText(text) }
}

private func encodeToText<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let text = String(data: try encoder.encode(value), encoding: .utf8) else { throw MessageCodingError.notUTF8 }
    return text
}

private func decodeFromText<T: Decodable>(_ text: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(text.utf8))
}
