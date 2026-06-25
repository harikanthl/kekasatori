//
//  RAGBudget.swift
//  MuseDrop
//
//  Provider-aware retrieval sizing. The on-device Apple model has a hard ~4k
//  token window, so it stays conservative; cloud models (Claude/GPT/Gemini/
//  DeepSeek/GLM/…) have far larger windows, so we scale how many source
//  excerpts (RAG chunks) and how much fallback full-text we include per turn.
//

import Foundation

struct RAGBudget: Equatable {
    /// Number of retrieved RAG chunks to include in the context block.
    let chunkLimit: Int
    /// Character cap for the non-RAG fallback (raw source truncation).
    let fallbackChars: Int

    /// Conservative budget matching the on-device window. Also used as a safe
    /// default when the route can't be determined.
    static let onDevice = RAGBudget(chunkLimit: 5, fallbackChars: 12_000)

    static func forRoute(_ route: LLMRouter.Route) -> RAGBudget {
        switch route {
        case .onDevice, .unavailable:
            return .onDevice
        case .cloud(let model):
            return forCloudModel(model)
        }
    }

    static func forCloudModel(_ model: String) -> RAGBudget {
        let window = contextWindowTokens(for: model)

        // Reserve ~40% of the window for retrieved source excerpts; the rest is
        // headroom for the system prompt, conversation history, and the model's
        // own output.
        let ragTokens = Double(window) * 0.40
        let charsPerToken = 4.0
        let tokensPerChunk = 250.0   // ~900-char chunks (see TextChunker) ≈ 225–250 tokens

        let chunks = Int((ragTokens / tokensPerChunk).rounded())
        // Cap the chunk count so we don't make pathologically large requests;
        // the floor keeps small-window models at least as good as before.
        let chunkLimit = min(48, max(5, chunks))

        let fallbackChars = Int((ragTokens * charsPerToken).rounded())
        let clampedFallback = min(160_000, max(12_000, fallbackChars))

        return RAGBudget(chunkLimit: chunkLimit, fallbackChars: clampedFallback)
    }

    /// Approximate *input* context window (in tokens) for known model families.
    /// Matched by substring so version bumps and provider prefixes still resolve.
    /// Unknown cloud models fall back to a conservative window.
    static func contextWindowTokens(for model: String) -> Int {
        let id = model.lowercased()
        if id.contains("claude") || id.contains("fable") { return 200_000 }
        if id.contains("gemini") { return 1_000_000 }
        if id.contains("gpt-5") || id.contains("codex") { return 200_000 }
        if id.contains("gpt-4o") || id.contains("gpt-4.1")
            || id.contains("gpt-4-turbo") || id.contains("o1") || id.contains("o3") { return 128_000 }
        if id.contains("grok") { return 128_000 }
        if id.contains("deepseek") { return 64_000 }
        if id.contains("kimi") || id.contains("moonshot") { return 200_000 }
        if id.contains("glm") { return 128_000 }
        if id.contains("llama") { return 128_000 }
        if id.contains("qwen") { return 128_000 }
        if id.contains("mistral") || id.contains("mixtral") { return 32_000 }
        return 32_000
    }
}
