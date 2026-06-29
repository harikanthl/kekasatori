//
//  ModelCatalogService.swift
//  MuseDrop
//
//  Fetches OpenRouter's live model catalog (ids, context, modality, per-token
//  pricing) for Compare's model browser and cost meter. `parse` is pure.
//
//  API: https://openrouter.ai/api/v1/models
//

import Foundation

struct ModelCatalogService: Sendable {
    static let shared = ModelCatalogService()

    private static let endpoint = "https://openrouter.ai/api/v1/models"

    func fetch() async -> [CatalogModel] {
        guard let url = URL(string: Self.endpoint) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        return Self.parse(data)
    }

    /// Live model-ID listing for a provider, returning sorted chat-model IDs.
    /// Most providers expose an OpenAI-style `GET {baseURL}/models` with a Bearer
    /// key, but two need their own endpoint/auth:
    ///   • Gemini's OpenAI-compat layer has no `/models` — list from the native
    ///     `…/v1beta/models` (x-goog-api-key) and strip the `models/` prefix.
    ///   • Anthropic's `/v1/models` wants `x-api-key` + `anthropic-version`.
    static func listModelIDs(for preset: LLMProviderPreset,
                             baseURL: String,
                             apiKey: String?) async throws -> [String] {
        switch preset {
        case .gemini:
            return try await listGeminiModels(apiKey: apiKey)
        case .anthropic:
            return try await listAnthropicModels(apiKey: apiKey)
        default:
            return try await listOpenAICompatModels(baseURL: baseURL, apiKey: apiKey)
        }
    }

    /// `GET {baseURL}/models` with a Bearer key — the OpenAI shape.
    private static func listOpenAICompatModels(baseURL: String, apiKey: String?) async throws -> [String] {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, let url = URL(string: trimmed + "/models") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return try await run(request)
    }

    /// Gemini native list: `…/v1beta/models?pageSize=1000` with `x-goog-api-key`.
    /// Keeps only models that support `generateContent` and strips `models/`.
    private static func listGeminiModels(apiKey: String?) async throws -> [String] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(status: http.statusCode, body: "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return [] }
        let ids = models.compactMap { m -> String? in
            guard let name = m["name"] as? String else { return nil }
            if let methods = m["supportedGenerationMethods"] as? [String],
               !methods.contains("generateContent") { return nil }
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
        guard !ids.isEmpty else { throw LLMError.http(status: 0, body: "No models returned.") }
        return ids.sorted()
    }

    /// Anthropic native list: `GET /v1/models` with `x-api-key` + version header.
    private static func listAnthropicModels(apiKey: String?) async throws -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models?limit=1000") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return try await run(request)
    }

    /// Shared executor for endpoints that return the OpenAI `{"data":[{"id":…}]}`
    /// shape (or a close variant). Throws on non-2xx or empty.
    private static func run(_ request: URLRequest) async throws -> [String] {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMError.http(status: http.statusCode, body: "")
        }
        let ids = parseModelIDs(data)
        guard !ids.isEmpty else { throw LLMError.http(status: 0, body: "No models returned.") }
        return ids
    }

    /// Extract model IDs from the OpenAI shape (`{"data":[{"id":…}]}`) plus a few
    /// common variants (a `{"models":[…]}` object or a bare array).
    private static func parseModelIDs(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        func ids(_ array: [[String: Any]]) -> [String] {
            array.compactMap { ($0["id"] ?? $0["name"]) as? String }
        }
        if let obj = json as? [String: Any] {
            if let arr = obj["data"] as? [[String: Any]] { return ids(arr).sorted() }
            if let arr = obj["models"] as? [[String: Any]] { return ids(arr).sorted() }
            if let arr = obj["models"] as? [String] { return arr.sorted() }
        }
        if let arr = json as? [[String: Any]] { return ids(arr).sorted() }
        if let arr = json as? [String] { return arr.sorted() }
        return []
    }

    /// Decode the `/models` response into CatalogModels, sorted by name. Pure.
    static func parse(_ data: Data) -> [CatalogModel] {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        let models = (decoded.data ?? []).compactMap { entry -> CatalogModel? in
            guard let id = entry.id, !id.isEmpty else { return nil }
            return CatalogModel(
                id: id,
                name: entry.name ?? id,
                contextLength: entry.context_length,
                promptPrice: Double(entry.pricing?.prompt ?? "") ?? 0,
                completionPrice: Double(entry.pricing?.completion ?? "") ?? 0,
                modality: entry.architecture?.modality
            )
        }
        return models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Wire format

    private struct Response: Decodable {
        let data: [Entry]?

        struct Entry: Decodable {
            let id: String?
            let name: String?
            let context_length: Int?
            let pricing: Pricing?
            let architecture: Architecture?

            struct Pricing: Decodable { let prompt: String?; let completion: String? }
            struct Architecture: Decodable { let modality: String? }
        }
    }
}
