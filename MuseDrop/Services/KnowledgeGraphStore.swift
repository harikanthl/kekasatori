//
//  KnowledgeGraphStore.swift
//  MuseDrop
//
//  Phase M3: the temporal knowledge-graph store. Upsert entities (deduped),
//  assert relations with validity windows, and resolve contradictions by closing
//  a single-valued fact's window when a new value is asserted — so the graph keeps
//  history and answers "what was true when". Local-first JSON in injectable
//  UserDefaults + injectable clock → fully unit-tested. Extraction (memory →
//  graph) is heuristic/LLM and lands with the agent (G); this is the substrate.
//

import Foundation

@MainActor
final class KnowledgeGraphStore: ObservableObject {
    static let shared = KnowledgeGraphStore()

    @Published private(set) var entities: [Entity]
    @Published private(set) var relations: [Relation]

    private let defaults: UserDefaults
    private let clock: () -> Date
    private static let entitiesKey = "cockpit.kg.entities"
    private static let relationsKey = "cockpit.kg.relations"

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.clock = clock
        self.entities = Self.load([Entity].self, key: Self.entitiesKey, from: defaults) ?? []
        self.relations = Self.load([Relation].self, key: Self.relationsKey, from: defaults) ?? []
    }

    // MARK: Entities

    func entity(_ id: UUID) -> Entity? { entities.first { $0.id == id } }

    func findEntity(type: EntityType, name: String) -> Entity? {
        let key = "\(type.rawValue):\(name.lowercased())"
        return entities.first { $0.key == key }
    }

    /// Insert or merge an entity (deduped by type + case-insensitive name).
    @discardableResult
    func upsertEntity(type: EntityType, name: String, aliases: [String] = []) -> Entity {
        if let existing = findEntity(type: type, name: name) {
            if !aliases.isEmpty, let idx = entities.firstIndex(where: { $0.id == existing.id }) {
                let merged = Set(entities[idx].aliases).union(aliases)
                entities[idx].aliases = Array(merged).sorted()
                persistEntities()
                return entities[idx]
            }
            return existing
        }
        let entity = Entity(type: type, name: name, aliases: aliases)
        entities.append(entity)
        persistEntities()
        return entity
    }

    // MARK: Relations

    /// Assert `from —predicate→ to`. When `singleValued`, any *other* live value
    /// for the same (from, predicate) is closed (validTo = now) before adding the
    /// new fact — that's contradiction resolution that preserves history. Asserting
    /// the identical live triple is idempotent.
    @discardableResult
    func assert(
        from: UUID,
        predicate: String,
        to: UUID,
        singleValued: Bool = false,
        at date: Date? = nil,
        sourceMemory: UUID? = nil
    ) -> Relation {
        let now = date ?? clock()

        if let existing = relations.first(where: {
            $0.isLive && $0.from == from && $0.predicate == predicate && $0.to == to
        }) {
            return existing   // idempotent
        }

        if singleValued {
            for idx in relations.indices where
                relations[idx].isLive && relations[idx].from == from
                && relations[idx].predicate == predicate && relations[idx].to != to {
                relations[idx].validTo = now
            }
        }

        let relation = Relation(from: from, predicate: predicate, to: to,
                                validFrom: now, sourceMemory: sourceMemory)
        relations.append(relation)
        persistRelations()
        return relation
    }

    /// Relations that held at `date` ("what was true when").
    func relations(at date: Date) -> [Relation] {
        relations.filter { $0.isValid(at: date) }
    }

    func liveRelations() -> [Relation] { relations.filter(\.isLive) }

    func relationsFrom(_ id: UUID) -> [Relation] { relations.filter { $0.from == id && $0.isLive } }
    func relationsTo(_ id: UUID) -> [Relation] { relations.filter { $0.to == id && $0.isLive } }

    /// Entities one live hop away (either direction).
    func neighbors(of id: UUID) -> [Entity] {
        let ids = Set(relationsFrom(id).map(\.to)).union(relationsTo(id).map(\.from))
        return ids.compactMap(entity)
    }

    // MARK: Persistence

    private func persistEntities() {
        if let data = try? JSONEncoder().encode(entities) { defaults.set(data, forKey: Self.entitiesKey) }
    }
    private func persistRelations() {
        if let data = try? JSONEncoder().encode(relations) { defaults.set(data, forKey: Self.relationsKey) }
    }
    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
