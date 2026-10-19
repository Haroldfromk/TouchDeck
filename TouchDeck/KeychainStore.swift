import Foundation
import Security

/// 기기 ID와 페어링 토큰을 Keychain에 둔다. 토큰은 맥에 내 기기임을 증명하는 비밀 값이다.
enum KeychainStore {
    private static let service = "com.harold.TouchDeck"

    static func deviceId() -> String {
        if let id = read("deviceId") { return id }
        let id = UUID().uuidString
        write("deviceId", id)
        return id
    }

    static func token() -> String? { read("token") }
    static func setToken(_ token: String) { write("token", token) }
    static func clearToken() { delete("token") }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ account: String, _ value: String) {
        delete(account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
