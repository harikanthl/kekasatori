//
//  OpenAlexProvider.swift
//  MuseDrop
//
//  ScholarlyProvider backed by the OpenAlex Works API. Abstracts arrive as an
//  inverted index (word -> positions) and are reconstructed here. An optional
//  `mailto` opts into OpenAlex's faster "polite pool". `parse` is pure.
//
//  API: https://api.openalex.org/works?search=<q>&per_page=<n>
//

import Foundation

struct OpenAlexProvider: ScholarlyProvider {
    let id: ScholarlyProviderID = .openAlex

    /// Optional contact email for OpenAlex's polite pool (faster, recommended).
    var mailto: String?

    init(mailto: String? = nil) {
        self.mailto = mailto
    }

    private static let endpoint = "https://api.openalex.org/works"

    func search(_ query: String, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }
        return try await fetchWorks([
            URLQueryItem(name: "search", value: trimmed),
            URLQueryItem(name: "per_page", value: String(Self.cap(limit)))
        ])
    }

    func search(_ query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }
        var items = [
            URLQueryItem(name: "search", value: trimmed),
            URLQueryItem(name: "per_page", value: String(Self.cap(limit)))
        ]
        switch sort {
        case .newest:    items.append(URLQueryItem(name: "sort", value: "publication_date:desc"))
        case .mostCited: items.append(URLQueryItem(name: "sort", value: "cited_by_count:desc"))
        case .relevance: break
        }
        if let since {
            items.append(URLQueryItem(name: "filter", value: "from_publication_date:\(Self.dateString(since))"))
        }
        return try await fetchWorks(items)
    }

    /// Most-cited recent works for the Trending feed. Anchored to a broad ML
    /// search so the global citation ranking stays AI-relevant; `since` bounds
    /// the publication window (nil = all time).
    /// Most-cited works. A `concept` id (e.g. "C31972630") gives a precise
    /// domain filter; otherwise the broad `search` anchor keeps it AI-relevant.
    func mostCited(search: String = "machine learning",
                   concept: String? = nil,
                   since: Date?,
                   limit: Int) async throws -> [PaperHit] {
        var items = [
            URLQueryItem(name: "sort", value: "cited_by_count:desc"),
            URLQueryItem(name: "per_page", value: String(Self.cap(limit)))
        ]
        // Restrict to research articles — otherwise highly-cited book/journal
        // series (e.g. "Materials Science Forum") dominate the ranking.
        var filters: [String] = ["type:article"]
        if let concept, !concept.isEmpty {
            filters.append("concepts.id:\(concept)")
        } else {
            items.insert(URLQueryItem(name: "search", value: search.isEmpty ? "machine learning" : search), at: 0)
        }
        if let since {
            filters.append("from_publication_date:\(Self.dateString(since))")
        }
        if !filters.isEmpty {
            items.append(URLQueryItem(name: "filter", value: filters.joined(separator: ",")))
        }
        return try await fetchWorks(items)
    }

    private static func cap(_ limit: Int) -> Int { max(1, min(limit, 100)) }

    /// Shared `/works` request path: append the polite-pool mailto, fetch, parse.
    private func fetchWorks(_ items: [URLQueryItem]) async throws -> [PaperHit] {
        var components = URLComponents(string: Self.endpoint)
        var allItems = items
        if let mailto, !mailto.isEmpty {
            allItems.append(URLQueryItem(name: "mailto", value: mailto))
        }
        components?.queryItems = allItems
        guard let url = components?.url else { throw ScholarlyError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholarlyError.http(status: -1) }
        guard (200...299).contains(http.statusCode) else { throw ScholarlyError.http(status: http.statusCode) }
        return try Self.parse(data)
    }

    /// `yyyy-MM-dd` in GMT, the format OpenAlex date filters expect.
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Decode an OpenAlex `/works` response into PaperHits. Pure & synchronous.
    static func parse(_ data: Data) throws -> [PaperHit] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded: OAResponse
        do {
            decoded = try decoder.decode(OAResponse.self, from: data)
        } catch {
            throw ScholarlyError.decoding(error.localizedDescription)
        }
        return (decoded.results ?? []).compactMap { $0.toHit() }
    }

    /// Rebuild abstract text from OpenAlex's `{word: [positions]}` inverted index.
    static func reconstructAbstract(_ index: [String: [Int]]?) -> String {
        guard let index, !index.isEmpty else { return "" }
        var positioned: [(position: Int, word: String)] = []
        for (word, positions) in index {
            for position in positions { positioned.append((position, word)) }
        }
        positioned.sort { $0.position < $1.position }
        return positioned.map(\.word).joined(separator: " ")
    }

    /// Extract an arXiv id from an arxiv.org `/abs/` or `/pdf/` URL, else nil.
    static func arxivId(in urlString: String?) -> String? {
        guard let urlString, urlString.contains("arxiv.org") else { return nil }
        for marker in ["/abs/", "/pdf/"] {
            guard let range = urlString.range(of: marker) else { continue }
            var id = String(urlString[range.upperBound...])
            if let q = id.firstIndex(where: { $0 == "?" || $0 == "#" }) { id = String(id[..<q]) }
            if id.lowercased().hasSuffix(".pdf") { id = String(id.dropLast(4)) }
            let trimmed = id.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Strip a DOI URL/`doi:` prefix down to the bare DOI.
    static func normalizeDOI(_ raw: String?) -> String? {
        guard var doi = raw, !doi.isEmpty else { return nil }
        let lower = doi.lowercased()
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:"] where lower.hasPrefix(prefix) {
            doi = String(doi.dropFirst(prefix.count))
            break
        }
        return doi.isEmpty ? nil : doi
    }

    // MARK: - Wire format

    private struct OAResponse: Decodable {
        let results: [OAWork]?
    }

    private struct OAWork: Decodable {
        let title: String?
        let displayName: String?
        let publicationYear: Int?
        let doi: String?
        let citedByCount: Int?
        let abstractInvertedIndex: [String: [Int]]?
        let authorships: [OAAuthorship]?
        let primaryLocation: OALocation?
        let openAccess: OAOpenAccess?

        func toHit() -> PaperHit? {
            let resolvedTitle = displayName ?? title
            guard let resolvedTitle,
                  !resolvedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let landing = primaryLocation?.landingPageUrl
            let pdf = primaryLocation?.pdfUrl ?? openAccess?.oaUrl
            // Many OpenAlex works are arXiv papers — recover the id from the
            // landing/PDF URL so they get a thumbnail + Add-to-Library + dedupe.
            let arxivId = OpenAlexProvider.arxivId(in: landing)
                ?? OpenAlexProvider.arxivId(in: pdf)
            return PaperHit(
                title: resolvedTitle,
                authors: (authorships ?? []).compactMap { $0.author?.displayName },
                abstract: OpenAlexProvider.reconstructAbstract(abstractInvertedIndex),
                year: publicationYear,
                venue: primaryLocation?.source?.displayName,
                doi: OpenAlexProvider.normalizeDOI(doi),
                arxivId: arxivId,
                url: landing,
                pdfURL: pdf,
                citationCount: citedByCount,
                sources: [ScholarlyProviderID.openAlex.rawValue]
            )
        }
    }

    private struct OAAuthorship: Decodable {
        let author: OAAuthor?
    }

    private struct OAAuthor: Decodable {
        let displayName: String?
    }

    private struct OALocation: Decodable {
        let landingPageUrl: String?
        let pdfUrl: String?
        let source: OASource?
    }

    private struct OASource: Decodable {
        let displayName: String?
    }

    private struct OAOpenAccess: Decodable {
        let oaUrl: String?
    }
}
