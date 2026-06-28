//
//  LocalInferenceService.swift
//  MuseDrop
//
//  Detects host-native, OpenAI-compatible inference servers (Ollama, LM Studio,
//  llama.cpp) and exposes their models as ModelProfiles so they can join the
//  Compare arena. First step of Run (Phase 3a): host-native accelerated models.
//  Probes are short-timeout and failure-tolerant — absent servers just yield [].
//

import Foundation

struct LocalInferenceService: Sendable {
    static let shared = LocalInferenceService()

    private struct Server {
        let name: String
        let baseURL: String     // OpenAI-compatible base (…/v1)
        let probe: String       // URL to list models
        let kind: Kind
        enum Kind { case ollamaTags, openAIModels }
    }

    private static let servers: [Server] = [
        Server(name: "Ollama", baseURL: "http://localhost:11434/v1",
               probe: "http://localhost:11434/api/tags", kind: .ollamaTags),
        Server(name: "LM Studio", baseURL: "http://localhost:1234/v1",
               probe: "http://localhost:1234/v1/models", kind: .openAIModels),
        Server(name: "llama.cpp", baseURL: "http://localhost:8080/v1",
               probe: "http://localhost:8080/v1/models", kind: .openAIModels)
    ]

    /// Probe each known server and return a profile per available model.
    func detectModels() async -> [ModelProfile] {
        var profiles: [ModelProfile] = []
        for server in Self.servers {
            guard let url = URL(string: server.probe) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                continue
            }
            let ids = server.kind == .ollamaTags ? Self.parseOllamaTags(data) : Self.parseOpenAIModels(data)
            for id in ids {
                profiles.append(ModelProfile(
                    label: "\(id) · \(server.name)",
                    preset: .custom,
                    modelId: id,
                    baseURL: server.baseURL
                ))
            }
        }
        return profiles
    }

    /// Parse Ollama's `/api/tags` → model names. Pure.
    static func parseOllamaTags(_ data: Data) -> [String] {
        struct Response: Decodable {
            let models: [Model]?
            struct Model: Decodable { let name: String? }
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (decoded.models ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
    }

    /// Parse an OpenAI `/v1/models` response → model ids. Pure.
    static func parseOpenAIModels(_ data: Data) -> [String] {
        struct Response: Decodable {
            let data: [Model]?
            struct Model: Decodable { let id: String? }
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (decoded.data ?? []).compactMap { $0.id }.filter { !$0.isEmpty }
    }
}
