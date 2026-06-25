//
//  LLMClient.swift
//  MuseDrop
//
//  Provider-agnostic chat interface. Implementations: OpenAICompatibleLLMClient
//  (OpenRouter / OpenAI / DeepSeek / Kimi / Gemini-compat / custom) and the
//  on-device route via LLMRouter.
//

import Foundation

enum LLMRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

struct LLMMessage: Codable, Sendable {
    var role: LLMRole
    var content: String

    init(_ role: LLMRole, _ content: String) {
        self.role = role
        self.content = content
    }
}

enum LLMError: LocalizedError {
    case notConfigured(String)
    case missingAPIKey
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
    case cancelled
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let detail): return detail
        case .missingAPIKey: return "Add an API key in Settings → AI Providers to use this provider."
        case .invalidURL: return "The provider base URL is invalid."
        case .http(let status, let body):
            let trimmed = body.count > 300 ? String(body.prefix(300)) + "…" : body
            return "Provider error (\(status)): \(trimmed)"
        case .decoding(let detail): return "Could not read the model response: \(detail)"
        case .cancelled: return "Request cancelled."
        case .unavailable(let detail): return detail
        }
    }
}

/// A streaming-capable chat client.
protocol LLMClient: Sendable {
    /// Stream assistant text deltas. Throws on transport/HTTP errors.
    func stream(messages: [LLMMessage], model: String) -> AsyncThrowingStream<String, Error>
}

extension LLMClient {
    /// Convenience: accumulate the full response from the stream.
    func complete(messages: [LLMMessage], model: String) async throws -> String {
        var text = ""
        for try await delta in stream(messages: messages, model: model) {
            text += delta
        }
        return text
    }
}
