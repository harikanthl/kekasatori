//
//  MemoryCapture.swift
//  MuseDrop
//
//  Phase M1: turn cockpit activity into memories. Structured events (a finished
//  Run, a DeepResearch brief) take the heuristic fast path — no LLM — building a
//  concise `RawObservation` the store embeds. Chat-turn and LLM-extraction capture
//  arrive with the agent (M2/G). Builders are pure (nonisolated) so they unit-test
//  without a store; the `capture` helpers write into the shared store.
//

import Foundation

enum MemoryCapture {

    // MARK: Builders (pure)

    /// An episodic memory for a finished run, scoped to its workspace. Returns nil
    /// for non-terminal or canceled runs (low signal).
    static func observation(for run: Run) -> RawObservation? {
        let statusText: String
        switch run.status {
        case .succeeded:       statusText = "succeeded"
        case .failed(let why): statusText = "failed (\(why))"
        case .canceled, .queued, .provisioning, .running: return nil
        }

        var text = "\(run.kind.rawValue.capitalized) run \(statusText)"
        if !run.metrics.isEmpty {
            text += " — " + run.metrics.map { "\($0.label) \(format($0.value))" }.joined(separator: ", ")
        }
        if let cost = run.costUSD, cost > 0 {
            text += " · $\(String(format: "%.4f", cost))"
        }

        let scope: MemoryScope = run.workspaceID.map { .workspace($0) } ?? .global
        return RawObservation(text: text, kind: .episodic, source: .run(run.id), scope: scope)
    }

    /// A semantic memory summarising a DeepResearch brief.
    static func observation(for brief: ResearchBrief) -> RawObservation {
        let snippet = String(brief.text.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = snippet.isEmpty ? "Research — \(brief.title)" : "Research — \(brief.title): \(snippet)"
        return RawObservation(text: text, kind: .semantic, source: .brief(brief.id), scope: .global)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }

    // MARK: Hooks (write into the store)

    @MainActor static func capture(_ run: Run) { capture(run, into: LocalMemoryStore.shared) }
    @MainActor static func capture(_ brief: ResearchBrief) { capture(brief, into: LocalMemoryStore.shared) }

    @MainActor
    static func capture(_ run: Run, into store: any MemoryStore) {
        if let observation = observation(for: run) { store.remember(observation) }
    }

    @MainActor
    static func capture(_ brief: ResearchBrief, into store: any MemoryStore) {
        store.remember(observation(for: brief))
    }
}
