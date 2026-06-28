//
//  HFRouterService.swift
//  Kekasatori
//
//  Fetches the Hugging Face Inference Providers router catalog
//  (`GET https://router.huggingface.co/v1/models`) — an OpenAI-compatible model
//  list where each model carries a `providers[]` array with per-provider context
//  length, token pricing, capabilities, latency and throughput. We surface this
//  as a browsable catalog so HF models join the Compare arena (and the Run eval
//  harness) as first-class `ModelProfile`s. The list is public; a token only
//  personalizes it. Parsing is pure and tested; the network call is best-effort.
//

import Foundation

/// One router model and the providers that serve it.
struct HFRouterModel: Identifiable, Equatable {
    let id: String              // e.g. "zai-org/GLM-5.2"
    let ownedBy: String
    let inputModalities: [String]
    let providers: [Provider]

    struct Provider: Equatable {
        let name: String
        let isLive: Bool
        let contextLength: Int?
        let inputPrice: Double?     // USD per 1M input tokens
        let outputPrice: Double?
        let isFree: Bool
        let supportsTools: Bool
        let latencyMs: Double?
        let throughput: Double?     // tokens/sec

        /// Blended price used for "cheapest" ranking; nil when unpriced.
        var blendedPrice: Double? {
            guard let inputPrice, let outputPrice else { return isFree ? 0 : nil }
            return inputPrice + outputPrice
        }
    }

    /// Short owner/name for display ("zai-org/GLM-5.2" → "GLM-5.2").
    var shortName: String { id.split(separator: "/").last.map(String.init) ?? id }
    var isMultimodal: Bool { inputModalities.contains("image") }
    var liveProviders: [Provider] { providers.filter(\.isLive) }

    /// Cheapest live provider (free counts as 0); falls back to any live provider.
    var cheapestProvider: Provider? {
        let live = liveProviders
        let priced = live.compactMap { p -> (Provider, Double)? in
            p.blendedPrice.map { (p, $0) }
        }
        if let best = priced.min(by: { $0.1 < $1.1 }) { return best.0 }
        return live.first
    }

    /// Largest advertised context across live providers.
    var maxContextLength: Int? { liveProviders.compactMap(\.contextLength).max() }
    var hasFreeProvider: Bool { liveProviders.contains { $0.isFree } }
}

enum HFRouterService {
    static let modelsURL = "https://router.huggingface.co/v1/models"

    /// Fetch + parse the catalog. Empty on any failure (offline, etc.). A token is
    /// optional — the list is public — but is sent when present.
    static func fetchCatalog(token: String? = nil) async -> [HFRouterModel] {
        guard let url = URL(string: modelsURL) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        return parse(data)
    }

    /// Pure parse of the router `/v1/models` payload. Tolerant of missing fields.
    static func parse(_ data: Data) -> [HFRouterModel] {
        guard let root = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }
        return root.data.compactMap { raw in
            guard let id = raw.id, !id.isEmpty else { return nil }
            let providers = (raw.providers ?? []).map { p in
                HFRouterModel.Provider(
                    name: p.provider ?? "?",
                    isLive: (p.status ?? "").lowercased() == "live",
                    contextLength: p.context_length,
                    inputPrice: p.pricing?.input,
                    outputPrice: p.pricing?.output,
                    isFree: p.is_free ?? false,
                    supportsTools: p.supports_tools ?? false,
                    latencyMs: p.first_token_latency_ms,
                    throughput: p.throughput
                )
            }
            return HFRouterModel(
                id: id,
                ownedBy: raw.owned_by ?? (id.split(separator: "/").first.map(String.init) ?? ""),
                inputModalities: raw.architecture?.input_modalities ?? ["text"],
                providers: providers
            )
        }
    }

    // MARK: - Decodable mirror of the router payload

    private struct Payload: Decodable { let data: [RawModel] }

    private struct RawModel: Decodable {
        let id: String?
        let owned_by: String?
        let architecture: Architecture?
        let providers: [RawProvider]?
        struct Architecture: Decodable { let input_modalities: [String]? }
    }

    private struct RawProvider: Decodable {
        let provider: String?
        let status: String?
        let context_length: Int?
        let pricing: Pricing?
        let is_free: Bool?
        let supports_tools: Bool?
        let first_token_latency_ms: Double?
        let throughput: Double?
        struct Pricing: Decodable { let input: Double?; let output: Double? }
    }
}
