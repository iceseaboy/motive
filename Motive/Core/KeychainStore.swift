//
//  KeychainStore.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation
import Security

enum KeychainStore {
    /// Read a value from keychain
    /// kSecAttrAccessible: Allow access when device is unlocked
    static func read(service: String, account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Write a value to keychain
    /// kSecAttrAccessible: Allow access when device is unlocked, don't migrate to new device
    static func write(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        
        // First try to delete existing item to avoid conflicts
        delete(service: service, account: account)
        
        // Add new item with proper access control
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            // Allow access when unlocked, app-specific (no keychain sharing)
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Delete a value from keychain
    static func delete(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
