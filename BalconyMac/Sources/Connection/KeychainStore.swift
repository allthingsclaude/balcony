import Foundation
import Security

/// Minimal Keychain wrapper for persisting small strings (the Mac's TLS cert + private key PEM).
///
/// The Mac app is not sandboxed, so no access group is required. Items are stored
/// `kSecAttrAccessibleAfterFirstUnlock` so the server can start after a reboot before the user
/// logs in interactively.
enum KeychainStore {
    private static let service = "com.balcony.mac.tls"

    /// Read a stored string for `account`, or nil if absent.
    static func string(forKey account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Store (overwriting any existing value) a string for `account`. Returns success.
    @discardableResult
    static func set(_ value: String, forKey account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
