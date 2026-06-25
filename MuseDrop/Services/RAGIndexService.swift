//
//  RAGIndexService.swift
//  MuseDrop
//
//  Retrieval-augmented context for the Tutor, backed by VecturaKit.
//  One vector index per library item. Embeddings are on-device by default
//  (VecturaNLKit) — no key, private, offline.
//

import Foundation
import VecturaKit
import VecturaNLKit

struct RetrievedChunk: Sendable {
    let text: String
    let score: Float
}

actor RAGIndexService {
    static let shared = RAGIndexService()

    private var stores: [UUID: VecturaKit] = [:]
    private var embedder: NLContextualEmbedder?
    /// content hash per item, so we don't re-ingest unchanged text.
    private var ingestedHash: [UUID: Int] = [:]
    private let logService = LogService.shared

    private init() {}

    private func sharedEmbedder() async throws -> NLContextualEmbedder {
        if let embedder { return embedder }
        let created = try await NLContextualEmbedder(language: .english)
        embedder = created
        return created
    }

    private func store(for downloadId: UUID) async throws -> VecturaKit {
        if let existing = stores[downloadId] { return existing }
        let dir = PathUtils.applicationSupportDirectory
            .appendingPathComponent("RAG", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let config = try VecturaConfig(
            name: "tutor-\(downloadId.uuidString)",
            directoryURL: dir,
            dimension: nil,
            searchOptions: VecturaConfig.SearchOptions(
                defaultNumResults: 6,
                minThreshold: 0.0,
                hybridWeight: 0.5
            )
        )
        let db = try await VecturaKit(config: config, embedder: try await sharedEmbedder())
        stores[downloadId] = db
        return db
    }

    /// Index `text` for an item if its content changed. Safe to call repeatedly.
    func ingest(downloadId: UUID, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 200 else { return }       // too short to bother
        let hash = trimmed.hashValue
        if ingestedHash[downloadId] == hash { return }   // unchanged

        do {
            let db = try await store(for: downloadId)
            let existing = try await db.documentCount
            if existing > 0 { try await db.reset() }      // re-index on change
            let chunks = TextChunker.chunk(trimmed)
            guard !chunks.isEmpty else { return }
            _ = try await db.addDocuments(texts: chunks, ids: nil)
            ingestedHash[downloadId] = hash
            logService.info("RAG indexed \(chunks.count) chunks for \(downloadId)")
        } catch {
            logService.warning("RAG ingest failed: \(error.localizedDescription)")
        }
    }

    /// Retrieve the most relevant chunks for a query.
    func retrieve(downloadId: UUID, query: String, limit: Int = 5) async -> [RetrievedChunk] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        do {
            let db = try await store(for: downloadId)
            guard try await db.documentCount > 0 else { return [] }
            let results = try await db.search(query: .text(q), numResults: limit, threshold: nil)
            return results.map { RetrievedChunk(text: $0.text, score: $0.score) }
        } catch {
            logService.warning("RAG retrieve failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Drop an item's index (e.g. on delete).
    func remove(downloadId: UUID) async {
        if let db = stores[downloadId] {
            try? await db.reset()
        }
        stores[downloadId] = nil
        ingestedHash[downloadId] = nil
    }
}
