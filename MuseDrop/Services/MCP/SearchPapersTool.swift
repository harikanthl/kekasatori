//
//  SearchPapersTool.swift
//  MuseDrop
//
//  The `search_papers` MCP tool, isolated so it can be linked into the headless
//  `kekasatori-mcp` CLI target WITHOUT dragging in VecturaKit (RAG) or SwiftData
//  (Library). Depends only on `MCPTool` + `PaperHit`. The full `LibraryMCPTools`
//  aggregator (app target) reuses this builder.
//

import Foundation

enum SearchPapersTool {
    /// Build the `search_papers` tool. `run` performs the actual search (injected
    /// so it's testable and so the CLI can wire `ScholarlySearchService.shared`).
    static func make(run: @escaping @Sendable (_ query: String, _ limit: Int) async -> [PaperHit]) -> MCPTool {
        MCPTool.typed(
            name: "search_papers",
            description: "Search the scholarly literature (arXiv, Semantic Scholar, OpenAlex) and return ranked, deduplicated results with titles, authors, year, venue, identifiers, and open-access status.",
            inputSchemaJSON: """
            {"type":"object","properties":{"query":{"type":"string","description":"Search query (keywords or a question)."},"limit":{"type":"integer","description":"Max results to return (1-50, default 20).","minimum":1,"maximum":50}},"required":["query"]}
            """
        ) { (args: Args) -> Result in
            let limit = min(max(args.limit ?? 20, 1), 50)
            let hits = await run(args.query, limit)
            return Result(papers: hits.prefix(limit).map(Projection.init))
        }
    }

    fileprivate struct Args: Decodable {
        let query: String
        let limit: Int?
    }

    fileprivate struct Result: Encodable {
        let papers: [Projection]
    }

    fileprivate struct Projection: Encodable {
        let title: String
        let authors: [String]
        let year: Int?
        let venue: String?
        let doi: String?
        let arxivId: String?
        let url: String?
        let openAccess: Bool

        init(_ hit: PaperHit) {
            title = hit.title
            authors = hit.authors
            year = hit.year
            venue = hit.venue
            doi = hit.doi
            arxivId = hit.arxivId
            url = hit.externalURLString
            openAccess = hit.isOpenAccess
        }
    }
}
