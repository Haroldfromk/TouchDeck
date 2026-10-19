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
/// 키보드의 볼륨 키와 같은 것. 맥이 같은 신호를 내서, 출력 장치에 맞는 쪽(macOS나 BetterDisplay)이 받는다.
public enum VolumeKey: String, Codable, Sendable {
    case up, down, mute
}

/// 숫자 키패드의 키. 맥에서 앞에 떠 있는 앱에 이 키를 누른 것처럼 입력한다.
/// JSON에서는 "0"~"9", "tab", "delete", "enter" 글자 하나로 보낸다.
public enum TypedKey: Equatable, Hashable, Sendable, Codable {
    case digit(Int)
    case tab, delete, enter

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        switch text {
        case "tab": self = .tab
        case "delete": self = .delete
        case "enter": self = .enter
        default:
            guard text.count == 1, let digit = Int(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown key \(text)"))
            }
            self = .digit(digit)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .digit(let d): try c.encode(String(d))
        case .tab: try c.encode("tab")
        case .delete: try c.encode("delete")
        case .enter: try c.encode("enter")
        }
    }
}

/// 허락받기 전에는 hello, pair, auth만 그대로 보낸다. 나머지는 SecureChannel 봉투에 넣어 보낸다.
public enum ClientMessage: Equatable, Sendable {
    case hello(deviceId: String, deviceName: String, nonce: String)
    /// 숫자는 보내지 않는다. 기기의 임시 공개 키(base64)와 "같은 숫자를 안다"는 증명만 보낸다.
    case pair(publicKey: String, proof: String)
    case auth(proof: String)
    case press(page: Int, index: Int)
    case getApps
    case setButton(page: Int, index: Int, button: DeckButton)
    case clearButton(page: Int, index: Int)
    case setVolume(Int)
    case volumeKey(VolumeKey)
    case typeKey(TypedKey)
    /// 폴더 고르기: 이 폴더("~" 또는 "~/…")의 하위 폴더 목록을 달라
    case listFolder(path: String)
}

/// 맥 → 기기
/// 허락 전 메시지(needPairing ~ unauthorized)는 그대로, 나머지는 SecureChannel 봉투에 넣어 보낸다.
public enum ServerMessage: Equatable, Sendable {
    /// 맥의 임시 공개 키(base64)와 맥 쪽 nonce
    case needPairing(publicKey: String, nonce: String)
    case pairingFailed(remaining: Int)
    /// 틀린 횟수를 다 써서 잠김. 맥 메뉴에서 풀어야 한다.
    case pairingLocked
    /// 토큰은 보내지 않는다. 맥도 같은 숫자를 안다는 증명만 보낸다.
    case paired(proof: String)
    /// 맥 쪽 nonce와 "맥이 토큰을 안다"는 증명
    case challenge(nonce: String, proof: String)
    case authorized
    case unauthorized
    case layout(DeckLayout)
    case apps([AppInfo])
    case pressResult(page: Int, index: Int, ok: Bool, message: String?)
    /// available == false: 지금 출력 장치(예: DisplayPort 모니터)는 macOS가 소리 크기를 모른다. 값을 못 보여준다.
    /// keysAllowed == false: 맥 앱에 손쉬운 사용 권한이 없어서 볼륨 키 신호를 못 보낸다.
    case volume(value: Int, muted: Bool, available: Bool, keysAllowed: Bool)
    /// 폴더 고르기 답. children은 하위 폴더 이름(숨김 폴더, 앱 제외). 없는 폴더거나 홈 밖이면 ok == false
    case folder(path: String, children: [String], ok: Bool)
}

/// 모든 메시지가 쓰는 JSON 키. 최상위 `type`으로 종류를 나눈다.
private enum Key: String, CodingKey {
    case type, deviceId, deviceName, publicKey, proof, page, index, button, value
    case remaining, nonce, pages, items, ok, message, muted, available, keysAllowed, key, path, children
}

extension ClientMessage: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hello":
            self = .hello(deviceId: try c.decode(String.self, forKey: .deviceId),
                          deviceName: try c.decode(String.self, forKey: .deviceName),
                          nonce: try c.decode(String.self, forKey: .nonce))
        case "pair":
            self = .pair(publicKey: try c.decode(String.self, forKey: .publicKey), proof: try c.decode(String.self, forKey: .proof))
        case "auth": self = .auth(proof: try c.decode(String.self, forKey: .proof))
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
        case "volumeKey": self = .volumeKey(try c.decode(VolumeKey.self, forKey: .key))
        case "typeKey": self = .typeKey(try c.decode(TypedKey.self, forKey: .key))
        case "listFolder": self = .listFolder(path: try c.decode(String.self, forKey: .path))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .hello(let deviceId, let deviceName, let nonce):
            try c.encode("hello", forKey: .type)
            try c.encode(deviceId, forKey: .deviceId)
            try c.encode(deviceName, forKey: .deviceName)
            try c.encode(nonce, forKey: .nonce)
        case .pair(let publicKey, let proof):
            try c.encode("pair", forKey: .type)
            try c.encode(publicKey, forKey: .publicKey)
            try c.encode(proof, forKey: .proof)
        case .auth(let proof):
            try c.encode("auth", forKey: .type)
            try c.encode(proof, forKey: .proof)
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
        case .volumeKey(let key):
            try c.encode("volumeKey", forKey: .type)
            try c.encode(key, forKey: .key)
        case .typeKey(let key):
            try c.encode("typeKey", forKey: .type)
            try c.encode(key, forKey: .key)
        case .listFolder(let path):
            try c.encode("listFolder", forKey: .type)
            try c.encode(path, forKey: .path)
        }
    }
}

extension ServerMessage: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "needPairing":
            self = .needPairing(publicKey: try c.decode(String.self, forKey: .publicKey), nonce: try c.decode(String.self, forKey: .nonce))
        case "pairingLocked": self = .pairingLocked
        case "pairingFailed": self = .pairingFailed(remaining: try c.decode(Int.self, forKey: .remaining))
        case "paired": self = .paired(proof: try c.decode(String.self, forKey: .proof))
        case "challenge":
            self = .challenge(nonce: try c.decode(String.self, forKey: .nonce), proof: try c.decode(String.self, forKey: .proof))
        case "authorized": self = .authorized
        case "unauthorized": self = .unauthorized
        case "layout": self = .layout(DeckLayout(pages: try c.decode([DeckPage].self, forKey: .pages)))
        case "apps": self = .apps(try c.decode([AppInfo].self, forKey: .items))
        case "pressResult":
            self = .pressResult(page: try c.decode(Int.self, forKey: .page),
                                index: try c.decode(Int.self, forKey: .index),
                                ok: try c.decode(Bool.self, forKey: .ok),
                                message: try c.decodeIfPresent(String.self, forKey: .message))
        case "folder":
            self = .folder(path: try c.decode(String.self, forKey: .path), children: try c.decode([String].self, forKey: .children),
                           ok: try c.decode(Bool.self, forKey: .ok))
        case "volume":
            self = .volume(value: try c.decode(Int.self, forKey: .value), muted: try c.decode(Bool.self, forKey: .muted),
                           available: try c.decodeIfPresent(Bool.self, forKey: .available) ?? true,
                           keysAllowed: try c.decodeIfPresent(Bool.self, forKey: .keysAllowed) ?? true)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .needPairing(let publicKey, let nonce):
            try c.encode("needPairing", forKey: .type)
            try c.encode(publicKey, forKey: .publicKey)
            try c.encode(nonce, forKey: .nonce)
        case .pairingLocked:
            try c.encode("pairingLocked", forKey: .type)
        case .pairingFailed(let remaining):
            try c.encode("pairingFailed", forKey: .type)
            try c.encode(remaining, forKey: .remaining)
        case .paired(let proof):
            try c.encode("paired", forKey: .type)
            try c.encode(proof, forKey: .proof)
        case .challenge(let nonce, let proof):
            try c.encode("challenge", forKey: .type)
            try c.encode(nonce, forKey: .nonce)
            try c.encode(proof, forKey: .proof)
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
        case .folder(let path, let children, let ok):
            try c.encode("folder", forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(children, forKey: .children)
            try c.encode(ok, forKey: .ok)
        case .volume(let value, let muted, let available, let keysAllowed):
            try c.encode("volume", forKey: .type)
            try c.encode(value, forKey: .value)
            try c.encode(muted, forKey: .muted)
            try c.encode(available, forKey: .available)
            try c.encode(keysAllowed, forKey: .keysAllowed)
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
