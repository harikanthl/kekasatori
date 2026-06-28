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
