//
//  Run.swift
//  MuseDrop
//
//  The cockpit's uniform execution object. Everything that runs — a code snippet,
//  an eval harness, a notebook cell, an agent step — becomes a `Run` with the same
//  telemetry, regardless of *where* it executes (see `ComputeBackend`). Phase A of
//  the cockpit plan (docs/cockpit-architecture.md): the `RunEvent` stream is the
//  single seam the CodeBox, Run pillar, and future GPU backend all share.
//

import Foundation

/// What kind of work a run represents. Drives labelling and (later) routing.
enum RunKind: String, Codable, Equatable, Sendable {
    case script        // a code snippet (CodeBox / Learn)
    case harness       // an eval harness (lm-eval, inspect, DeepSpec)
    case notebookCell  // a single notebook cell (Phase E)
    case agentStep     // a step taken by the coding-agent operator (Phase G)
    case server        // a long-lived server (local inference / notebook kernel)
}

/// The lifecycle of a run. `failed` carries a human-readable reason.
enum RunStatus: Equatable, Codable, Sendable {
    case queued
    case provisioning   // remote target spinning up (Phase B/D)
    case running
    case succeeded
    case failed(String)
    case canceled

    /// True once the run has reached a final state.
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .canceled: return true
        case .queued, .provisioning, .running: return false
        }
    }
}

/// One thing that happened during a run. A `ComputeBackend` yields a stream of
/// these; the UI and the `Run` record both fold them in the same way, so local
/// and remote execution look identical downstream.
enum RunEvent: Equatable, Sendable {
    case status(RunStatus)
    case log(String)
    case metric(EvalMetric)
    case artifact(URL)
    case cost(Double)   // running cost in USD (remote targets)
}

/// What to execute, independent of where. `code` needs staging into a workdir;
/// `command` is a pre-built container argument list (e.g. from `EvalRunService`).
/// Transient — not persisted (hence not Codable).
struct RunRequest: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case code(CodeRunSpec)
        case command([String])
    }

    var kind: RunKind
    var payload: Payload
    /// Optional human-readable command for the UI (key-masked by the caller).
    var displayCommand: String?

    init(kind: RunKind, payload: Payload, displayCommand: String? = nil) {
        self.kind = kind
        self.payload = payload
        self.displayCommand = displayCommand
    }

    /// Convenience for the common CodeBox/Learn path.
    static func code(_ spec: CodeRunSpec, kind: RunKind = .script) -> RunRequest {
        RunRequest(kind: kind, payload: .code(spec))
    }
}

/// The persisted record of a single execution. Built by folding the `RunEvent`
/// stream — `apply(_:)` is the one place events become state, so the CodeBox, Run
/// pillar, and (later) a RunStore all stay consistent.
struct Run: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var workspaceID: UUID?
    var kind: RunKind
    var status: RunStatus
    var log: String
    var metrics: [EvalMetric]
    var artifacts: [URL]
    var costUSD: Double?
    var startedAt: Date?
    var endedAt: Date?
    let createdAt: Date

    init(id: UUID = UUID(), workspaceID: UUID? = nil, kind: RunKind, createdAt: Date = Date()) {
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.status = .queued
        self.log = ""
        self.metrics = []
        self.artifacts = []
        self.costUSD = nil
        self.startedAt = nil
        self.endedAt = nil
        self.createdAt = createdAt
    }

    /// Fold one event into the record. `now` is injectable for deterministic tests.
    mutating func apply(_ event: RunEvent, now: Date = Date()) {
        switch event {
        case .status(let newStatus):
            status = newStatus
            if case .running = newStatus, startedAt == nil { startedAt = now }
            if newStatus.isTerminal, endedAt == nil { endedAt = now }
        case .log(let line):
            log += line
        case .metric(let metric):
            metrics.append(metric)
        case .artifact(let url):
            artifacts.append(url)
        case .cost(let usd):
            costUSD = usd
        }
    }
}
