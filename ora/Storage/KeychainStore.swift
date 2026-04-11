//
//  KeychainStore.swift
//  ora
//
//  Tiny Keychain wrapper for per-provider API keys. One generic-password
//  item per provider id, keyed by a fixed service string so all ora
//  credentials group together in Keychain Access.app.
//
//  Ora isn't sandboxed (see ora.entitlements), so these items land in
//  the default login keychain without any keychain-access-group gymnastics.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "co.ora.apikeys"

    enum Failure: Error {
        case osStatus(OSStatus)
    }

    /// Stores `key` under `provider`. Overwrites any existing value.
    /// Pass an empty string to delete — we treat "" as "no credential"
    /// rather than persisting a zero-length secret.
    static func setAPIKey(_ key: String, provider: String) throws {
        if key.isEmpty {
            removeAPIKey(provider: provider)
            return
        }
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { throw Failure.osStatus(addStatus) }
        default:
            throw Failure.osStatus(status)
        }
    }

    /// Returns the stored key for `provider`, or `nil` if missing.
    static func apiKey(provider: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return nil }
        return string
    }

    static func removeAPIKey(provider: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
