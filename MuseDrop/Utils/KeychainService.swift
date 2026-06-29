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
        /// Hugging Face access token (`hf_…`) — the Inference Providers router and
        /// any other HF surface (Endpoints, Jobs) share this one token.
        static let huggingFace = "huggingface.apiKey"
        /// RunPod API key — the Serverless OpenAI-compatible endpoints (Compare /
        /// Run) and, later, raw GPU provisioning (Phase 3b) share this one key.
        static let runPod = "runpod.apiKey"
        /// Modal proxy token pair (`Modal-Key` / `Modal-Secret`) for the compute
        /// dial's Modal GPU backend (a deployed Modal web endpoint).
        static let modalKey = "modal.key"
        static let modalSecret = "modal.secret"
        /// Kaggle API credentials (from kaggle.json) — injected as
        /// KAGGLE_USERNAME / KAGGLE_KEY into Learn data lessons that pull a real
        /// Kaggle dataset.
        static let kaggleUsername = "kaggle.username"
        static let kaggleKey = "kaggle.apiKey"
        /// Optional separate embeddings key (e.g. OpenAI text-embedding) for cloud RAG.
        static let embeddings = "llm.embeddings.apiKey"
        /// Google Gemini key (aistudio) — shared by the podcast generator and the
        /// Gemini tutor/Compare provider (the same key works for both surfaces).
        static let gemini = "gemini.apiKey"
        /// Per-provider BYOK keys for the first-class OpenAI-compatible providers,
        /// so a user can store several and switch without re-entering. OpenRouter
        /// and Custom continue to share `llmChat`.
        static let anthropic = "anthropic.apiKey"
        static let openai = "openai.apiKey"
        static let xai = "xai.apiKey"
        static let deepseek = "deepseek.apiKey"
        static let groq = "groq.apiKey"
        static let mistral = "mistral.apiKey"
        /// Optional GitHub personal-access token — lifts the repo-search rate
        /// limit for the Discover GitHub source (10→30 req/min). Read-only; only
        /// public search is used, so no scopes are required.
        static let githubToken = "github.apiKey"
        /// Secret key for the user's community (Nostr) identity. Placeholder
        /// until the real Nostr signer lands — kept here so it never touches
        /// UserDefaults, SwiftData, or logs.
        static let communitySecretKey = "community.identity.secretKey"
    }
}
