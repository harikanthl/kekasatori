//
//  KnowledgeGraph.swift
//  MuseDrop
//
//  Phase M3: the temporal knowledge graph behind agentic memory
//  (docs/agentic-memory.md). Entities (papers, models, methods, results…) linked
//  by relations that carry validity windows, so the store answers "what was true
//  when" and resolves contradictions by closing a fact's window rather than
//  deleting it (Zep/Graphiti-style).
//

import Foundation

enum EntityType: String, Codable, Sendable, CaseIterable {
    case paper, model, method, dataset, hyperparameter, result, tool, person, concept
}

struct Entity: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var type: EntityType
    var name: String
    var aliases: [String]

    init(id: UUID = UUID(), type: EntityType, name: String, aliases: [String] = []) {
        self.id = id
        self.type = type
        self.name = name
        self.aliases = aliases
    }

    /// Dedupe key — same type + case-insensitive name is the same entity.
    var key: String { "\(type.rawValue):\(name.lowercased())" }
}

struct Relation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var from: UUID          // Entity.id
    var predicate: String   // "uses" | "improves" | "achieved" | "trained-on" …
    var to: UUID            // Entity.id
    var validFrom: Date
    var validTo: Date?      // nil = still true
    var sourceMemory: UUID?

    init(id: UUID = UUID(), from: UUID, predicate: String, to: UUID,
         validFrom: Date, validTo: Date? = nil, sourceMemory: UUID? = nil) {
        self.id = id
        self.from = from
        self.predicate = predicate
        self.to = to
        self.validFrom = validFrom
        self.validTo = validTo
        self.sourceMemory = sourceMemory
    }

    /// Whether the fact held at `date` (half-open window `[validFrom, validTo)`).
    func isValid(at date: Date) -> Bool {
        date >= validFrom && (validTo == nil || date < validTo!)
    }

    var isLive: Bool { validTo == nil }
}
