import Foundation
import Security

/// Thin wrapper over a `kSecClassGenericPassword` item set, keyed by account.
///
/// Everything is stored with `kSecAttrAccessibleAfterFirstUnlock` so a rewrite
/// triggered right after login still finds its key.
nonisolated enum Keychain {
    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Returns the stored secret, or `nil` if there is none.
    static func read(service: String = Constants.keychainService, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Adds the secret, or updates it in place when one already exists.
    @discardableResult
    static func write(_ value: String,
                      service: String = Constants.keychainService,
                      account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query = baseQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Item exists: update the payload (and re-assert accessibility) instead.
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        return status == errSecSuccess
    }

    /// Removes the secret. Succeeds when there was nothing to remove.
    @discardableResult
    static func delete(service: String = Constants.keychainService, account: String) -> Bool {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
