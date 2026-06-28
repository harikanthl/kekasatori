//
//  LibraryMCPTools.swift
//  MuseDrop
//
//  Phase 5a.1 — the cockpit's capabilities as MCP tools (the `library-mcp` skill
//  from the plan). Read-only v1: scholarly search, on-device RAG retrieval, and
//  Library listing. Dependencies are injected (closures) so the tools unit-test
//  against stubs without network or the SwiftData store; the defaults wire to the
//  real services for the eventual headless helper.
//
//  Deferred to v2: run_eval / provision_gpu (spawn containers / remote GPUs —
//  security-sensitive, need consent + budget caps).
//

import Foundation

struct LibraryMCPTools: Sendable {
    var searchPapers: @Sendable (_ query: String, _ limitPerProvider: Int) async -> [PaperHit]
    var ragQuery: @Sendable (_ downloadId: UUID, _ query: String, _ limit: Int) async -> [RetrievedChunk]
    var listLibrary: @Sendable () async -> [DownloadItem]

    init(
        searchPapers: @escaping @Sendable (String, Int) async -> [PaperHit] = { query, limit in
            await ScholarlySearchService.shared.search(query, limitPerProvider: limit)
        },
        ragQuery: @escaping @Sendable (UUID, String, Int) async -> [RetrievedChunk] = { id, query, limit in
            await RAGIndexService.shared.retrieve(downloadId: id, query: query, limit: limit)
        },
        listLibrary: @escaping @Sendable () async -> [DownloadItem] = {
            await MainActor.run { DataStore.shared.fetchAllDownloads() }
        }
    ) {
        self.searchPapers = searchPapers
        self.ragQuery = ragQuery
        self.listLibrary = listLibrary
    }

    func tools() -> [MCPTool] {
        [searchPapersTool, ragQueryTool, searchLibraryTool]
    }

    // MARK: - search_papers (shared with the CLI target)

    private var searchPapersTool: MCPTool {
        SearchPapersTool.make(run: searchPapers)
    }

    // MARK: - rag_query

    private var ragQueryTool: MCPTool {
        let run = ragQuery
        return MCPTool.typed(
            name: "rag_query",
            description: "Retrieve the passages most relevant to a query from a Library item's full text, using the on-device index. Returns ranked text chunks with similarity scores.",
            inputSchemaJSON: """
            {"type":"object","properties":{"download_id":{"type":"string","description":"UUID of the Library item to query."},"query":{"type":"string","description":"What to retrieve."},"limit":{"type":"integer","description":"Max passages (1-20, default 5).","minimum":1,"maximum":20}},"required":["download_id","query"]}
            """
        ) { (args: RagArgs) -> ChunksResult in
            let limit = Self.clamp(args.limit ?? 5, 1, 20)
            let chunks = await run(args.downloadId, args.query, limit)
            return ChunksResult(chunks: chunks.map { ChunkProjection(text: $0.text, score: $0.score) })
        }
    }

    // MARK: - search_library

    private var searchLibraryTool: MCPTool {
        let list = listLibrary
        return MCPTool.typed(
            name: "search_library",
            description: "List or filter the user's Library (downloaded papers, audio, video). Omit the query to list everything (most recent first).",
            inputSchemaJSON: """
            {"type":"object","properties":{"query":{"type":"string","description":"Case-insensitive filter over title and format. Omit to list all."},"limit":{"type":"integer","description":"Max items (1-100, default 50).","minimum":1,"maximum":100}},"required":[]}
            """
        ) { (args: LibraryArgs) -> LibraryResult in
            let limit = Self.clamp(args.limit ?? 50, 1, 100)
            let all = await list()
            let q = (args.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let filtered = q.isEmpty
                ? all
                : all.filter { $0.displayTitle.lowercased().contains(q) || $0.format.lowercased().contains(q) }
            return LibraryResult(items: filtered.prefix(limit).map(LibraryItemProjection.init))
        }
    }

    // MARK: - Helpers

    static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), high)
    }
}

// MARK: - Argument types

private struct RagArgs: Decodable {
    let downloadId: UUID
    let query: String
    let limit: Int?
    enum CodingKeys: String, CodingKey {
        case downloadId = "download_id"
        case query, limit
    }
}

private struct LibraryArgs: Decodable {
    let query: String?
    let limit: Int?
}

// MARK: - Result projections (stable JSON shapes for clients)

private struct ChunksResult: Encodable { let chunks: [ChunkProjection] }
private struct LibraryResult: Encodable { let items: [LibraryItemProjection] }

private struct ChunkProjection: Encodable {
    let text: String
    let score: Float
}

private struct LibraryItemProjection: Encodable {
    let id: String
    let title: String
    let format: String
    let isPaper: Bool
    let createdDate: Date

    init(_ item: DownloadItem) {
        id = item.id.uuidString
        title = item.displayTitle
        format = item.displayFormat
        isPaper = item.isResearchDocument
        createdDate = item.createdDate
    }
}
