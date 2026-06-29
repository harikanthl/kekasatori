//
//  ScholarlySearchService.swift
//  MuseDrop
//
//  Fans a keyword query out across the configured ScholarlyProviders, merges
//  duplicate hits, and ranks the result. Phase 0 ships Semantic Scholar only;
//  arXiv + OpenAlex slot in by extending `providers` (Phase 1) — no call-site
//  changes. A failing provider degrades gracefully (logged, contributes []).
//

import Foundation

struct ScholarlySearchService: Sendable {
    let providers: [any ScholarlyProvider]

    init(providers: [any ScholarlyProvider]) {
        self.providers = providers
    }

    /// Default configuration: Semantic Scholar + arXiv + OpenAlex, queried
    /// concurrently and merged. All run keyless here; wire a Semantic Scholar
    /// key / OpenAlex mailto in a later phase to lift rate limits.
    static let shared = ScholarlySearchService(providers: [
        SemanticScholarProvider(),
        ArxivProvider(),
        OpenAlexProvider()
    ])

    /// Stable display/query order for the built-in providers. Scholarly metadata
    /// first; HuggingFace + GitHub (code/community sources) trail them.
    static let providerOrder: [ScholarlyProviderID] = [
        .semanticScholar, .arxiv, .openAlex, .europePmc, .huggingFace, .github
    ]

    static func makeProvider(_ id: ScholarlyProviderID) -> any ScholarlyProvider {
        switch id {
        case .semanticScholar: return SemanticScholarProvider()
        case .arxiv:           return ArxivProvider()
        case .openAlex:        return OpenAlexProvider()
        case .europePmc:       return EuropePmcProvider()
        case .huggingFace:     return HuggingFaceProvider()
        case .github:          return GitHubProvider()
        }
    }

    /// Build a service over just the enabled providers (Discover source toggles),
    /// preserving the canonical order.
    init(enabled: Set<ScholarlyProviderID>) {
        self.providers = Self.providerOrder
            .filter { enabled.contains($0) }
            .map { Self.makeProvider($0) }
    }

    /// Search every provider concurrently, then merge + rank.
    /// Returns [] for trivially short queries; never throws (provider failures
    /// are absorbed so one bad backend can't sink the whole search).
    func search(_ query: String, limitPerProvider: Int = 20) async -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let providers = self.providers
        var collected: [PaperHit] = []
        await withTaskGroup(of: [PaperHit].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.search(trimmed, limit: limitPerProvider)
                    } catch {
                        LogService.shared.debug(
                            "Scholarly provider \(provider.id.rawValue) failed for \"\(trimmed)\": \(error.localizedDescription)"
                        )
                        return []
                    }
                }
            }
            for await hits in group { collected.append(contentsOf: hits) }
        }

        return Self.rank(PaperHit.merge(collected))
    }

    /// Sort/time-filtered keyword search across every provider, merged and
    /// ordered by `sort`. Used by Discover's browse-by-task lens.
    func search(_ query: String, sort: PaperSort, since: Date?, limitPerProvider: Int = 20) async -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let providers = self.providers
        var collected: [PaperHit] = []
        await withTaskGroup(of: [PaperHit].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.search(trimmed, sort: sort, since: since, limit: limitPerProvider)
                    } catch {
                        LogService.shared.debug(
                            "Scholarly provider \(provider.id.rawValue) failed for \"\(trimmed)\": \(error.localizedDescription)"
                        )
                        return []
                    }
                }
            }
            for await hits in group { collected.append(contentsOf: hits) }
        }
        return Self.rank(PaperHit.merge(collected), by: sort)
    }

    /// Order a merged result set by the chosen lens. Pure & testable.
    static func rank(_ hits: [PaperHit], by sort: PaperSort) -> [PaperHit] {
        switch sort {
        case .relevance:
            // arXiv preprints first (fresh work isn't buried), then recent, then cited.
            return hits.sorted { lhs, rhs in
                let lArxiv = lhs.arxivId != nil, rArxiv = rhs.arxivId != nil
                if lArxiv != rArxiv { return lArxiv }
                if (lhs.year ?? 0) != (rhs.year ?? 0) { return (lhs.year ?? 0) > (rhs.year ?? 0) }
                return (lhs.citationCount ?? 0) > (rhs.citationCount ?? 0)
            }
        case .newest:
            return hits.sorted { ($0.year ?? 0, $0.citationCount ?? 0) > ($1.year ?? 0, $1.citationCount ?? 0) }
        case .mostCited:
            return hits.sorted { ($0.citationCount ?? -1, $0.year ?? 0) > ($1.citationCount ?? -1, $1.year ?? 0) }
        }
    }

    /// Most-cited first; ties broken by most-recent. Pure & testable.
    static func rank(_ hits: [PaperHit]) -> [PaperHit] {
        hits.sorted { lhs, rhs in
            let lc = lhs.citationCount ?? -1
            let rc = rhs.citationCount ?? -1
            if lc != rc { return lc > rc }
            return (lhs.year ?? 0) > (rhs.year ?? 0)
        }
    }
}
