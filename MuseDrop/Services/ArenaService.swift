//
//  ArenaService.swift
//  MuseDrop
//
//  Fans one prompt across several ModelProfiles for the Compare arena. Each
//  profile streams independently through the existing LLMRouter, so on-device
//  and any BYOK cloud models run side by side against the same key.
//

import Foundation

struct ArenaService: Sendable {
    static let shared = ArenaService()

    /// A streaming completion for one profile. Local/custom endpoints go straight
    /// to the OpenAI-compatible client (their own base URL, no shared cloud key,
    /// so the key never leaks to a localhost server); everything else routes
    /// through LLMRouter (on-device / OpenRouter BYOK).
    func stream(_ profile: ModelProfile, messages: [LLMMessage]) async -> AsyncThrowingStream<String, Error> {
        if profile.isLocal, let baseURL = profile.baseURL {
            let client = OpenAICompatibleLLMClient(baseURL: baseURL, apiKey: nil)
            return client.stream(messages: messages, model: profile.modelId)
        }
        // Providers with their own key + endpoint (Hugging Face router, RunPod
        // serverless): hit the OpenAI-compatible endpoint directly with that
        // provider's token, rather than LLMRouter (which keys off the OpenRouter
        // secret).
        if profile.preset == .huggingFace || profile.preset == .runPod,
           let ep = profile.directEndpoint {
            let client = OpenAICompatibleLLMClient(baseURL: ep.baseURL, apiKey: ep.apiKey)
            return client.stream(messages: messages, model: profile.modelId)
        }
        return await LLMRouter.shared.stream(messages: messages, settings: profile.settings)
    }
}
