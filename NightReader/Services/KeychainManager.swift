import Foundation
import Security

// MARK: - Keychain Manager
//
// Stores and retrieves the Claude API key from iOS Keychain.
//
//  ┌──────────┐   save(key)   ┌──────────────┐
//  │ Settings │──────────────▶│   Keychain    │
//  │   View   │               │  (encrypted)  │
//  └──────────┘               └──────┬───────┘
//                                     │ getKey()
//                             ┌───────▼───────┐
//                             │ ClaudeAPI      │
//                             │ Service        │
//                             └───────────────┘

enum KeychainManager {

    private static let service = "com.nightreader.api"
    private static let account = "claude-api-key"

    /// Save API key to Keychain. Returns true on success.
    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve API key from Keychain.
    static func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    /// Delete API key from Keychain.
    @discardableResult
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if API key is stored.
    static var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
