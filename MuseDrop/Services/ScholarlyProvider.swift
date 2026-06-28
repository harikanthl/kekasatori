//
//  ScholarlyProvider.swift
//  MuseDrop
//
//  Abstraction over scholarly search backends (Semantic Scholar, arXiv,
//  OpenAlex). Each provider takes a plain keyword query and returns normalized
//  PaperHit values; ScholarlySearchService fans out and dedupes across them.
//  Sibling abstraction to LLMClient. Phase 0 of the Discover pillar.
//

import Foundation

enum ScholarlyProviderID: String, Codable, Sendable, CaseIterable {
    case semanticScholar
    case arxiv
    case openAlex
    case europePmc

    var displayName: String {
        switch self {
        case .semanticScholar: return "Semantic Scholar"
        case .arxiv:           return "arXiv"
        case .openAlex:        return "OpenAlex"
        case .europePmc:       return "Europe PMC"
        }
    }
}

/// How to order a keyword search (Discover browse lens).
enum PaperSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case newest
    case mostCited

    var id: String { rawValue }
    var title: String {
        switch self {
        case .relevance:  return "Relevance"
        case .newest:     return "Newest"
        case .mostCited:  return "Most Cited"
        }
    }
}

/// A keyword-search backend for scholarly papers.
protocol ScholarlyProvider: Sendable {
    var id: ScholarlyProviderID { get }
    /// Search for `query`, returning up to `limit` normalized hits.
    func search(_ query: String, limit: Int) async throws -> [PaperHit]
    /// Sort/time-filtered search. Providers opt in; the default ignores the
    /// extra options and falls back to plain relevance search.
    func search(_ query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit]
}

extension ScholarlyProvider {
    func search(_ query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit] {
        try await search(query, limit: limit)
    }
}

enum ScholarlyError: LocalizedError {
    case invalidQuery
    case invalidURL
    case http(status: Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidQuery:        return "Search query is too short."
        case .invalidURL:          return "Could not build the search request URL."
        case .http(let status):    return "Scholarly provider HTTP error (\(status))."
        case .decoding(let detail): return "Could not read the provider response: \(detail)"
        }
    }
}
