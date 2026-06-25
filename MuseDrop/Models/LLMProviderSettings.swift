//
//  LLMProviderSettings.swift
//  MuseDrop
//
//  Non-secret BYOK configuration (provider preset, model id, base URL).
//  The API key itself is stored in the Keychain, never here.
//

import Foundation

enum LLMProviderPreset: String, CaseIterable, Identifiable, Codable {
    case onDevice
    case openRouter
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice:   return "On-Device (Apple Intelligence)"
        case .openRouter: return "OpenRouter (BYOK)"
        case .custom:     return "Custom (OpenAI-compatible)"
        }
    }

    /// Base URL for OpenAI-compatible providers. nil for on-device.
    var defaultBaseURL: String? {
        switch self {
        case .onDevice:   return nil
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .custom:     return ""
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .onDevice: return false
        case .openRouter, .custom: return true
        }
    }
}

/// Suggested model IDs for the OpenRouter preset (user can type any).
///
/// Labels are the user-facing names; ids are verified to exist on OpenRouter's
/// live `/models` catalog. (Composer and the Codex line aren't hosted on
/// OpenRouter, so they're intentionally omitted.) The user can still type any
/// custom id in Settings.
enum LLMModelPreset {
    static let openRouterSuggestions: [(label: String, id: String)] = [
        ("Opus 4.8", "anthropic/claude-opus-4.8"),
        ("GPT-5.5", "openai/gpt-5.5"),
        ("Sonnet 4.6", "anthropic/claude-sonnet-4.6"),
        ("Opus 4.7", "anthropic/claude-opus-4.7"),
        ("Fable 5", "anthropic/claude-fable-5"),
        ("Grok Build 0.1", "x-ai/grok-build-0.1"),
        ("GPT-5.4", "openai/gpt-5.4"),
        ("Opus 4.6", "anthropic/claude-opus-4.6"),
        ("Opus 4.5", "anthropic/claude-opus-4.5"),
        ("GPT-5.2", "openai/gpt-5.2"),
        ("Gemini 3.1 Pro", "google/gemini-3.1-pro-preview"),
        ("GPT-5.4 Mini", "openai/gpt-5.4-mini"),
        ("GPT-5.4 Nano", "openai/gpt-5.4-nano"),
        ("Haiku 4.5", "anthropic/claude-haiku-4.5"),
        ("Grok 4.3", "x-ai/grok-4.3"),
        ("Sonnet 4.5", "anthropic/claude-sonnet-4.5"),
        ("GPT-5.1", "openai/gpt-5.1"),
        ("Gemini 3 Flash", "google/gemini-3-flash-preview"),
        ("Gemini 3.5 Flash", "google/gemini-3.5-flash"),
        ("Sonnet 4", "anthropic/claude-sonnet-4"),
        ("GPT-5 Mini", "openai/gpt-5-mini"),
        ("Gemini 2.5 Flash", "google/gemini-2.5-flash"),
        ("Kimi K2.5", "moonshotai/kimi-k2.5"),
        ("GLM 5.2", "z-ai/glm-5.2")
    ]

    static let defaultOpenRouterModel = "anthropic/claude-sonnet-4.6"
}

/// Persisted, non-secret provider settings (UserDefaults-backed).
struct LLMProviderSettings: Codable, Equatable {
    var preset: LLMProviderPreset
    var modelId: String
    var baseURL: String
    /// When true and on-device is available, prefer it even if a cloud key exists.
    var preferOnDevice: Bool
    /// Enable retrieval-augmented context (RAG) for tutor answers.
    var enableRAG: Bool

    static let `default` = LLMProviderSettings(
        preset: .openRouter,
        modelId: LLMModelPreset.defaultOpenRouterModel,
        baseURL: LLMProviderPreset.openRouter.defaultBaseURL ?? "",
        preferOnDevice: true,
        enableRAG: true
    )

    // MARK: UserDefaults persistence

    private static let key = "llm.providerSettings"

    static func load() -> LLMProviderSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LLMProviderSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// The effective base URL (preset default unless custom overrides).
    var effectiveBaseURL: String {
        if preset == .custom { return baseURL }
        return preset.defaultBaseURL ?? baseURL
    }
}
