//
//  Memory.swift
//  MuseDrop
//
//  The agentic-memory atom (docs/agentic-memory.md, phase M0). A `Memory` is one
//  durable fact/experience the cockpit agent can recall across sessions. The
//  temporal/graph fields (validFrom/validTo/supersededBy) are carried now for
//  forward-compatibility but only exercised from M3/M4.
//

import Foundation

enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case episodic     // what happened (a run, a chat turn)
    case semantic     // a fact / relationship
    case procedural   // a reusable recipe
    case profile      // a stable user preference
}

enum MemorySource: Codable, Equatable, Sendable {
    case run(UUID)
    case chat
    case note(UUID)
    case transcript(UUID)
    case paper(String)
    case brief(UUID)
    case agentStep
    case manual
}

enum MemoryScope: Codable, Equatable, Sendable {
    case global
    case workspace(UUID)
}

struct Memory: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: MemoryKind
    var content: String
    var embedding: [Float]?
    var source: MemorySource
    var scope: MemoryScope
    var confidence: Double
    var validFrom: Date
    var validTo: Date?
    var supersededBy: UUID?
    var useCount: Int
    var lastUsedAt: Date?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: MemoryKind,
        content: String,
        embedding: [Float]? = nil,
        source: MemorySource = .manual,
        scope: MemoryScope = .global,
        confidence: Double = 1.0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.embedding = embedding
        self.source = source
        self.scope = scope
        self.confidence = confidence
        self.validFrom = createdAt
        self.validTo = nil
        self.supersededBy = nil
        self.useCount = 0
        self.lastUsedAt = nil
        self.createdAt = createdAt
    }

    /// Live = not retired and not superseded (the only memories recall returns).
    var isLive: Bool { validTo == nil && supersededBy == nil }
}

/// A captured event before extraction. M0 stores it as a single memory verbatim;
/// M1 adds LLM/on-device extraction into multiple facts + entities.
struct RawObservation: Sendable {
    var text: String
    var kind: MemoryKind
    var source: MemorySource
    var scope: MemoryScope

    init(text: String, kind: MemoryKind = .episodic, source: MemorySource = .manual, scope: MemoryScope = .global) {
        self.text = text
        self.kind = kind
        self.source = source
        self.scope = scope
    }
}

/// Criteria for selective forgetting (M4). A memory is forgotten when it matches
/// every provided field (AND). All-nil matches everything (an explicit clear).
struct ForgetSpec: Sendable {
    var olderThan: Date?
    var scope: MemoryScope?
    var kind: MemoryKind?
    var unusedOnly: Bool   // only memories never surfaced by recall (useCount == 0)

    init(olderThan: Date? = nil, scope: MemoryScope? = nil, kind: MemoryKind? = nil, unusedOnly: Bool = false) {
        self.olderThan = olderThan
        self.scope = scope
        self.kind = kind
        self.unusedOnly = unusedOnly
    }
}

/// A recall request — multi-signal retrieval ranks live memories against it.
struct MemoryQuery: Sendable {
    var text: String
    var scope: MemoryScope?   // nil = any scope
    var kind: MemoryKind?     // nil = any kind
    var limit: Int

    init(text: String, scope: MemoryScope? = nil, kind: MemoryKind? = nil, limit: Int = 8) {
        self.text = text
        self.scope = scope
        self.kind = kind
        self.limit = limit
    }
}
