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
    case huggingFace
    case runPod
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice:    return "On-Device (Apple Intelligence)"
        case .openRouter:  return "OpenRouter (BYOK)"
        case .huggingFace: return "Hugging Face (Router)"
        case .runPod:      return "RunPod (Serverless)"
        case .custom:      return "Custom (OpenAI-compatible)"
        }
    }

    /// Base URL for OpenAI-compatible providers. nil for on-device. RunPod is nil
    /// too: its endpoint is per-deployment (`…/v2/{id}/openai/v1`), so the full
    /// URL lives on the `ModelProfile`, not the preset.
    var defaultBaseURL: String? {
        switch self {
        case .onDevice:    return nil
        case .openRouter:  return "https://openrouter.ai/api/v1"
        case .huggingFace: return "https://router.huggingface.co/v1"
        case .runPod:      return nil
        case .custom:      return ""
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .onDevice: return false
        case .openRouter, .huggingFace, .runPod, .custom: return true
        }
    }

    /// Keychain account holding this preset's API key. nil when no key applies.
    var keychainAccount: String? {
        switch self {
        case .onDevice:    return nil
        case .openRouter:  return KeychainService.Account.llmChat
        case .huggingFace: return KeychainService.Account.huggingFace
        case .runPod:      return KeychainService.Account.runPod
        case .custom:      return KeychainService.Account.llmChat
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

/// Heuristic capability checks for a model id. Used to gate vision (multimodal)
/// requests so we never attach images to a text-only model.
enum LLMModelCapabilities {
    /// Whether the model can accept image input. Conservative: unknown/custom
    /// ids default to `false` so figure analysis silently no-ops rather than
    /// erroring against a text-only endpoint.
    static func supportsVision(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        // Known vision-capable families on OpenRouter / OpenAI-compatible gateways.
        if id.contains("claude") { return true }            // Claude 3+ are multimodal
        if id.contains("gemini") { return true }
        if id.contains("gpt-5") || id.contains("gpt-4o") || id.contains("gpt-4.1") { return true }
        if id.contains("grok-4") || id.contains("grok-build") || id.contains("grok-2-vision") { return true }
        if id.contains("glm-5") || id.contains("glm-4v") { return true }
        if id.contains("vision") || id.contains("-vl") || id.contains("multimodal") { return true }
        return false
    }
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
    /// Opt-in: send figure/chart page images to a vision-capable cloud model to
    /// extract graph data and tables. Requires a cloud key and a vision model.
    /// Off by default — images leave the device only when the user enables this.
    var analyzeFigures: Bool

    init(preset: LLMProviderPreset,
         modelId: String,
         baseURL: String,
         preferOnDevice: Bool,
         enableRAG: Bool,
         analyzeFigures: Bool = false) {
        self.preset = preset
        self.modelId = modelId
        self.baseURL = baseURL
        self.preferOnDevice = preferOnDevice
        self.enableRAG = enableRAG
        self.analyzeFigures = analyzeFigures
    }

    static let `default` = LLMProviderSettings(
        preset: .openRouter,
        modelId: LLMModelPreset.defaultOpenRouterModel,
        baseURL: LLMProviderPreset.openRouter.defaultBaseURL ?? "",
        preferOnDevice: true,
        enableRAG: true,
        analyzeFigures: false
    )

    // MARK: Codable (resilient to fields added across versions)

    private enum CodingKeys: String, CodingKey {
        case preset, modelId, baseURL, preferOnDevice, enableRAG, analyzeFigures
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = LLMProviderSettings.default
        preset = try c.decodeIfPresent(LLMProviderPreset.self, forKey: .preset) ?? fallback.preset
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? fallback.modelId
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? fallback.baseURL
        preferOnDevice = try c.decodeIfPresent(Bool.self, forKey: .preferOnDevice) ?? fallback.preferOnDevice
        enableRAG = try c.decodeIfPresent(Bool.self, forKey: .enableRAG) ?? fallback.enableRAG
        analyzeFigures = try c.decodeIfPresent(Bool.self, forKey: .analyzeFigures) ?? fallback.analyzeFigures
    }

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
