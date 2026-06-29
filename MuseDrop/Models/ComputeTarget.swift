//
//  ComputeTarget.swift
//  MuseDrop
//
//  Where a run executes — the cockpit's "compute dial". Local Docker/Apple
//  Container ↔ remote RunPod GPU are uniform values, so the same `RunRequest` can
//  be promoted from CPU to GPU by swapping the target (docs/cockpit-architecture.md
//  §3.3 / §7). Phase A only exercises `.local`; remote cases are wired in Phase B/D.
//

import Foundation

// ContainerEngine is a String-raw enum; Codable conformance is synthesized so it
// can be stored inside a (persisted) ComputeTarget.
extension ContainerEngine: Codable {}

struct ComputeTarget: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var location: Location
    var capabilities: Capabilities

    /// Where the work physically runs.
    enum Location: Codable, Equatable, Sendable {
        case local(engine: ContainerEngine)
        case runpodServerless(endpointID: String)   // ephemeral job (Phase B)
        case runpodPod(podID: String)               // persistent GPU session (Phase D)
        case modal(endpointURL: String)             // Modal web endpoint (job tier)
    }

    /// What the target can do — drives the dial UI, cost meter, and what kinds of
    /// runs are allowed (e.g. notebooks need `supportsInteractive`).
    struct Capabilities: Codable, Equatable, Sendable {
        var gpu: String?                // "A100 80GB", or nil for CPU
        var supportsInteractive: Bool   // can host a notebook/server kernel
        var supportsStreaming: Bool     // line-by-line logs
        var costPerHourUSD: Double?     // nil = free (local)
        var maxRuntime: TimeInterval?   // safety cap for paid targets

        static let localCPU = Capabilities(
            gpu: nil, supportsInteractive: true, supportsStreaming: true,
            costPerHourUSD: nil, maxRuntime: nil
        )
    }

    var isLocal: Bool {
        if case .local = location { return true }
        return false
    }

    var isPaid: Bool { (capabilities.costPerHourUSD ?? 0) > 0 }
}

extension ComputeTarget {
    /// Stable id for the local target so a user's selection survives runtime
    /// re-detection (the engine may change, the "This Mac" slot does not).
    static let localID = UUID(uuidString: "00000000-0000-0000-0000-0000000010CA")!

    /// Build the local target from a detected engine, or nil if none is ready.
    static func local(_ status: ContainerRuntimeStatus) -> ComputeTarget? {
        guard let engine = status.engine else { return nil }
        return ComputeTarget(
            id: localID,
            name: "This Mac · \(engine.displayName)",
            location: .local(engine: engine),
            capabilities: .localCPU
        )
    }
}
