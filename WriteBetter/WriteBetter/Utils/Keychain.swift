import Foundation
import Security

/// Thin wrapper over a `kSecClassGenericPassword` item set, keyed by account.
///
/// Items are written with `kSecAttrAccessibleAfterFirstUnlock`. On macOS that attribute
/// only takes effect in the data-protection keychain; these items live in the login
/// keychain, where access is governed by the keychain's lock state and the item's
/// access list (which is why a differently signed build can be asked for permission).
/// It is set anyway so the items behave the same if they ever move.
nonisolated enum Keychain {
    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    enum ReadResult: Equatable {
        case found(String)
        /// Nothing saved: the only case that means "the user has no key".
        case notFound
        /// The Keychain refused or failed (locked, access denied, …); a key may well exist.
        case failure(OSStatus)
    }

    /// Reads the stored secret, telling "no key" apart from "couldn't read it".
    static func readResult(service: String = Constants.keychainService, account: String) -> ReadResult {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8),
                  !value.isEmpty else { return .notFound }
            return .found(value)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failure(status)
        }
    }

    /// The stored secret, or `nil` when there is none or it couldn't be read.
    /// Use `readResult` where the difference matters.
    static func read(service: String = Constants.keychainService, account: String) -> String? {
        if case .found(let value) = readResult(service: service, account: account) { return value }
        return nil
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
