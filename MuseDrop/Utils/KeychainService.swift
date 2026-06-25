//
//  KeychainService.swift
//  MuseDrop
//
//  Secure storage for BYOK API keys. Keys live ONLY in the Keychain —
//  never in UserDefaults, SwiftData, or logs.
//

import Foundation
import Security

enum KeychainService {
    /// Service namespace for all MuseDrop secrets.
    private static let service = "com.kekasatori.apikeys"

    /// Store (or replace) a secret for the given account key. Empty value deletes it.
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else { return delete(account) }
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Replace if present.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Load a secret, or nil if absent.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// True if a non-empty secret exists for the account.
    static func has(_ account: String) -> Bool {
        guard let value = get(account) else { return false }
        return !value.isEmpty
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Known accounts

    enum Account {
        /// Chat LLM key (OpenRouter or any OpenAI-compatible gateway).
        static let llmChat = "llm.chat.apiKey"
        /// Optional separate embeddings key (e.g. OpenAI text-embedding) for cloud RAG.
        static let embeddings = "llm.embeddings.apiKey"
    }
}
