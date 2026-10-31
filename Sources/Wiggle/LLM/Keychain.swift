import Foundation
import Security

/// Stores API keys as generic passwords in the user's login Keychain.
///
/// Reading a secret can make macOS ask for permission, so each one is read at most once per launch,
/// and `contains` checks for one without reading it.
@MainActor
enum Keychain {
    enum Account: String {
        case anthropic = "anthropic-api-key"
        case openai = "openai-api-key"
        case photonSecret = "photon-project-secret"
    }

    private static let service = "com.noamankhalil.wiggle"
    private static var cache: [Account: String] = [:]

    /// Whether a secret is saved. Reads only its attributes, which needs no permission.
    static func contains(_ account: Account) -> Bool {
        if cache[account] != nil { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ account: Account) -> String? {
        if let cached = cache[account] { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = String(data: data, encoding: .utf8)
        else { return nil }
        cache[account] = value
        return value
    }

    /// Saves `value`, or deletes the key when `value` is empty.
    static func write(_ value: String, for account: Account) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        cache[account] = nil
        guard !value.isEmpty else { return }
        cache[account] = value

        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
