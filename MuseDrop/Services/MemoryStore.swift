//
//  MemoryStore.swift
//  MuseDrop
//
//  The local-first memory service (docs/agentic-memory.md, phase M0): remember /
//  recall / forget over a persisted, embedded store. Recall is multi-signal —
//  keyword overlap ∥ vector cosine — combined and ranked, scoped by workspace and
//  kind. M1 adds capture hooks + extraction; M3 the temporal knowledge graph.
//  Storage is injectable UserDefaults + an injectable `Embedder`, so the whole
//  thing is unit-tested without a real embedding model or disk.
//

import Foundation

@MainActor
protocol MemoryStore {
    var memories: [Memory] { get }
    func remember(_ observation: RawObservation)
    func recall(_ query: MemoryQuery) -> [Memory]
    func forget(_ id: UUID)
}

@MainActor
final class LocalMemoryStore: ObservableObject, MemoryStore {
    static let shared = LocalMemoryStore()

    @Published private(set) var memories: [Memory]

    private let defaults: UserDefaults
    private let embedder: Embedder
    private let limit: Int
    private static let storageKey = "cockpit.memories"

    init(
        defaults: UserDefaults = .standard,
        embedder: Embedder = HashingEmbedder(),
        limit: Int = 5_000
    ) {
        self.defaults = defaults
        self.embedder = embedder
        self.limit = limit
        self.memories = Self.load(from: defaults)
    }

    // MARK: Write

    func remember(_ observation: RawObservation) {
        let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Idempotent on exact duplicates within the same scope (cheap M0 dedup).
        if memories.contains(where: { $0.isLive && $0.scope == observation.scope && $0.content == text }) {
            return
        }
        var memory = Memory(kind: observation.kind, content: text,
                            source: observation.source, scope: observation.scope)
        memory.embedding = embedder.embed(text)
        memories.insert(memory, at: 0)
        if memories.count > limit { memories.removeLast(memories.count - limit) }
        persist()
    }

    func forget(_ id: UUID) {
        memories.removeAll { $0.id == id }
        persist()
    }

    // MARK: Read (multi-signal recall)

    func recall(_ query: MemoryQuery) -> [Memory] {
        let queryTokens = Set(HashingEmbedder.tokenize(query.text))
        let queryVec = embedder.embed(query.text)

        let scored: [(Memory, Double)] = memories.compactMap { memory in
            guard memory.isLive else { return nil }
            if let scope = query.scope, memory.scope != scope { return nil }
            if let kind = query.kind, memory.kind != kind { return nil }
            let score = Self.score(memory, queryTokens: queryTokens, queryVec: queryVec)
            return score > 0 ? (memory, score) : nil
        }

        let result = scored
            .sorted { $0.1 > $1.1 }
            .prefix(query.limit)
            .map(\.0)

        recordUsage(of: result.map(\.id))
        return result
    }

    /// Bump useCount / lastUsedAt for recalled memories — drives decay-based
    /// forgetting (frequently-recalled memories survive; cold ones can be reaped).
    private func recordUsage(of ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let now = Date()
        let idSet = Set(ids)
        for index in memories.indices where idSet.contains(memories[index].id) {
            memories[index].useCount += 1
            memories[index].lastUsedAt = now
        }
        persist()
    }

    // MARK: Consolidation & forgetting (M4)

    /// Collapse near-duplicate memories (same scope + kind, cosine ≥ threshold),
    /// keeping the newest and folding the older one's use count into it. Summarising
    /// episodic clusters into semantic facts is LLM-driven and lands with the agent.
    func consolidate(similarityThreshold: Float = 0.97) {
        var kept: [Memory] = []                 // newest-first (memories already is)
        var dropped = false
        for memory in memories {
            if let dupeIndex = kept.firstIndex(where: { other in
                other.kind == memory.kind && other.scope == memory.scope
                    && similarity(other, memory) >= similarityThreshold
            }) {
                kept[dupeIndex].useCount += memory.useCount   // fold usage into the survivor
                dropped = true
            } else {
                kept.append(memory)
            }
        }
        if dropped {
            memories = kept
            persist()
        }
    }

    /// Forget memories matching the spec (AND over provided fields).
    func forget(matching spec: ForgetSpec) {
        let before = memories.count
        memories.removeAll { memory in
            if let scope = spec.scope, memory.scope != scope { return false }
            if let kind = spec.kind, memory.kind != kind { return false }
            if let olderThan = spec.olderThan, memory.createdAt >= olderThan { return false }
            if spec.unusedOnly, memory.useCount > 0 { return false }
            return true
        }
        if memories.count != before { persist() }
    }

    private func similarity(_ a: Memory, _ b: Memory) -> Float {
        guard let va = a.embedding, let vb = b.embedding else { return 0 }
        return cosineSimilarity(va, vb)
    }

    /// Half keyword-overlap, half vector cosine — the two parallel signals.
    static func score(_ memory: Memory, queryTokens: Set<String>, queryVec: [Float]) -> Double {
        let memTokens = Set(HashingEmbedder.tokenize(memory.content))
        let keyword = queryTokens.isEmpty ? 0
            : Double(queryTokens.intersection(memTokens).count) / Double(queryTokens.count)
        let cosine = memory.embedding.map { Double(max(0, cosineSimilarity($0, queryVec))) } ?? 0
        return 0.5 * keyword + 0.5 * cosine
    }

    // MARK: Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(memories) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [Memory] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Memory].self, from: data) else {
            return []
        }
        return decoded
    }
}
