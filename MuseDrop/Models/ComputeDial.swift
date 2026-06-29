//
//  ComputeDial.swift
//  MuseDrop
//
//  Value types + pure helpers behind the compute dial (Phase C): a saved RunPod
//  compute endpoint, cost formatting, and the run guard that stops a paid run
//  before it overruns time or budget. All pure → unit-tested without UI/network.
//

import Foundation

/// A user-saved GPU job endpoint (RunPod serverless or a Modal web endpoint) for
/// the compute dial — distinct from the inference endpoints in Compare. Persisted
/// locally; the credentials live in the Keychain. Tolerant of the pre-provider
/// schema (a bare `endpointID`, no `provider`).
struct SavedComputeEndpoint: Identifiable, Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
        case runpod
        case modal
        var id: String { rawValue }
        var displayName: String { self == .runpod ? "RunPod" : "Modal" }
    }

    let id: UUID
    var name: String
    var provider: Provider
    /// RunPod endpoint id, or the Modal web-endpoint URL.
    var identifier: String
    var gpu: String
    var costPerHourUSD: Double

    init(id: UUID = UUID(), name: String, provider: Provider, identifier: String,
         gpu: String, costPerHourUSD: Double) {
        self.id = id
        self.name = name
        self.provider = provider
        self.identifier = identifier
        self.gpu = gpu
        self.costPerHourUSD = costPerHourUSD
    }

    /// Materialise the persisted endpoint as a live `ComputeTarget` for the dial.
    var asTarget: ComputeTarget {
        let location: ComputeTarget.Location = provider == .modal
            ? .modal(endpointURL: identifier)
            : .runpodServerless(endpointID: identifier)
        return ComputeTarget(
            id: id,
            name: name,
            location: location,
            capabilities: .init(gpu: gpu, supportsInteractive: false,
                                supportsStreaming: provider == .runpod,
                                costPerHourUSD: costPerHourUSD, maxRuntime: nil)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, identifier, endpointID, gpu, costPerHourUSD
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .runpod
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
            ?? c.decode(String.self, forKey: .endpointID)   // legacy schema
        gpu = try c.decode(String.self, forKey: .gpu)
        costPerHourUSD = try c.decode(Double.self, forKey: .costPerHourUSD)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(provider, forKey: .provider)
        try c.encode(identifier, forKey: .identifier)
        try c.encode(gpu, forKey: .gpu)
        try c.encode(costPerHourUSD, forKey: .costPerHourUSD)
    }
}

/// Cost rendering for the dial readout. Pure and locale-stable (fixed format).
enum ComputeCost {
    static func ratePerHour(_ usd: Double?) -> String? {
        guard let usd, usd > 0 else { return nil }
        return String(format: "$%.2f/hr", usd)
    }

    static func accrued(_ usd: Double?) -> String? {
        guard let usd else { return nil }
        return String(format: "$%.4f", usd)
    }
}

/// Stops a paid run before it overruns the target's max runtime or the user's
/// budget cap. Pure decision so the policy is testable in isolation.
enum RunGuard {
    static func shouldStop(
        elapsed: TimeInterval,
        maxRuntime: TimeInterval?,
        costUSD: Double?,
        costCapUSD: Double?
    ) -> Bool {
        if let maxRuntime, elapsed >= maxRuntime { return true }
        if let costUSD, let costCapUSD, costUSD >= costCapUSD { return true }
        return false
    }
}
