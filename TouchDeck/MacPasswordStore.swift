import Foundation
import LocalAuthentication
import Security

/// 맥 잠금 풀기에 쓸 맥 비밀번호. 이 아이폰 키체인에만 두고, 꺼낼 때마다 Face ID(안 되면 아이폰 비밀번호)를 거친다.
/// 아이폰에 암호를 설정해 둔 동안만 쓸 수 있고, iCloud 키체인으로 다른 기기에 퍼지지 않는다
enum MacPasswordStore {
    private static let service = "com.harold.TouchDeck.unlock"
    /// 아이폰 앱은 맥 하나와만 짝짓는다(토큰 하나). 그래서 칸도 하나
    private static let account = "macPassword"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Face ID를 묻지 않고 있는지만 본다
    static var hasPassword: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var q = baseQuery
        q[kSecUseAuthenticationContext as String] = context
        q[kSecReturnAttributes as String] = true
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// 저장 못 하면 이유를 돌려준다
    static func save(_ password: String) -> String? {
        delete()
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil) else {
            return "비밀번호를 저장하지 못했어요"
        }
        var q = baseQuery
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("[unlock] save failed:", status)
            return "아이폰에 암호가 설정돼 있어야 저장할 수 있어요"
        }
        return nil
    }

    /// 꺼낼 때 시스템이 Face ID를 묻는다. 취소하거나 실패하면 nil
    static func read(reason: String) async -> String? {
        await Task.detached {
            let context = LAContext()
            context.localizedReason = reason
            var q = baseQuery
            q[kSecReturnData as String] = true
            q[kSecUseAuthenticationContext as String] = context
            var result: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }.value
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
