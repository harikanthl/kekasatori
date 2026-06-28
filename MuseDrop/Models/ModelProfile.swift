//
//  ModelProfile.swift
//  MuseDrop
//
//  A named model configuration for the Compare arena — one column in the
//  side-by-side. It wraps LLMProviderSettings so the existing LLMRouter can run
//  it unchanged; OpenRouter profiles all share the single BYOK key, so several
//  models run at once against one key.
//

import Foundation

struct ModelProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var label: String
    var preset: LLMProviderPreset
    var modelId: String
    /// Base URL for `.custom` (local Ollama/LM Studio) profiles; nil otherwise.
    var baseURL: String?

    init(id: UUID = UUID(), label: String, preset: LLMProviderPreset, modelId: String, baseURL: String? = nil) {
        self.id = id
        self.label = label
        self.preset = preset
        self.modelId = modelId
        self.baseURL = baseURL
    }

    /// A local/custom OpenAI-compatible endpoint (its own base URL, no shared key).
    var isLocal: Bool { preset == .custom && (baseURL?.isEmpty == false) }

    /// Direct OpenAI-compatible endpoint (base URL + key) to run this model in the
    /// Compare arena and the Run eval harness, bypassing LLMRouter's on-device
    /// fallback (the chosen model always runs). nil for on-device, which has no
    /// HTTP endpoint. Local endpoints carry no key; HF/OpenRouter pull the preset's
    /// Keychain token.
    var directEndpoint: (baseURL: String, apiKey: String?)? {
        guard preset != .onDevice else { return nil }
        if isLocal { return (baseURL ?? "", nil) }
        let key = preset.keychainAccount.flatMap { KeychainService.get($0) }
        return (settings.effectiveBaseURL, key)
    }

    /// Router settings for this profile. Cloud profiles force preferOnDevice off
    /// so the chosen model actually runs (instead of falling back to on-device).
    var settings: LLMProviderSettings {
        LLMProviderSettings(
            preset: preset,
            modelId: modelId,
            baseURL: baseURL ?? preset.defaultBaseURL ?? "",
            preferOnDevice: preset == .onDevice,
            enableRAG: false,
            analyzeFigures: false
        )
    }

    /// Same model (ignoring the generated id) — for de-duping selections.
    func sameModel(as other: ModelProfile) -> Bool {
        preset == other.preset && modelId == other.modelId && baseURL == other.baseURL
    }

    static let onDevice = ModelProfile(label: "Apple Intelligence", preset: .onDevice, modelId: "on-device")

    /// Selectable models: on-device plus the OpenRouter suggestions.
    static var catalog: [ModelProfile] {
        [onDevice] + LLMModelPreset.openRouterSuggestions.map {
            ModelProfile(label: $0.label, preset: .openRouter, modelId: $0.id)
        }
    }

    static var defaultSelection: [ModelProfile] {
        [
            ModelProfile(label: "Opus 4.8", preset: .openRouter, modelId: "anthropic/claude-opus-4.8"),
            ModelProfile(label: "GPT-5.5", preset: .openRouter, modelId: "openai/gpt-5.5")
        ]
    }

    // MARK: - Persistence

    private static let key = "compare.profiles"

    static func loadSelected() -> [ModelProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ModelProfile].self, from: data),
              !decoded.isEmpty else {
            return defaultSelection
        }
        return decoded
    }

    static func saveSelected(_ profiles: [ModelProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
