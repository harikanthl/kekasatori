//
//  CatalogModel.swift
//  MuseDrop
//
//  A model from OpenRouter's live catalog — id, context, modality, and exact
//  per-token pricing. Powers Compare's model browser and the $/run cost meter.
//

import Foundation

struct CatalogModel: Identifiable, Sendable, Equatable {
    let id: String              // e.g. "anthropic/claude-opus-4.8"
    let name: String            // e.g. "Anthropic: Claude Opus 4.8"
    let contextLength: Int?
    let promptPrice: Double      // USD per prompt token
    let completionPrice: Double  // USD per completion token
    let modality: String?

    /// A selectable Compare profile for this model.
    var profile: ModelProfile {
        ModelProfile(label: name, preset: .openRouter, modelId: id)
    }

    var isFree: Bool { promptPrice == 0 && completionPrice == 0 }

    /// "$10.00 / $50.00 per M" style pricing, or "Free".
    var pricingLabel: String {
        if isFree { return "Free" }
        let inM = promptPrice * 1_000_000
        let outM = completionPrice * 1_000_000
        return String(format: "$%@ in · $%@ out / M", Self.trim(inM), Self.trim(outM))
    }

    private static func trim(_ value: Double) -> String {
        value >= 1 ? String(format: "%.2f", value) : String(format: "%.3f", value)
    }
}
