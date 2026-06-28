//
//  SemanticScholarProvider.swift
//  MuseDrop
//
//  ScholarlyProvider backed by the Semantic Scholar Graph API. Works without a
//  key (rate-limited); an optional API key lifts the limit. JSON parsing is a
//  pure static function (`parse`) so it can be unit-tested without the network.
//
//  API: https://api.semanticscholar.org/graph/v1/paper/search
//

import Foundation

struct SemanticScholarProvider: ScholarlyProvider {
    let id: ScholarlyProviderID = .semanticScholar

    /// Optional Semantic Scholar API key. nil → keyless (shared rate pool).
    var apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    private static let endpoint = "https://api.semanticscholar.org/graph/v1/paper/search"
    private static let fields = "title,abstract,authors,year,venue,externalIds,openAccessPdf,citationCount,url"

    func search(_ query: String, limit: Int) async throws -> [PaperHit] {
        try await fetch(query: query, sinceYear: nil, limit: limit)
    }

    func search(_ query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit] {
        // The relevance endpoint supports a `year` window but no server sort;
        // the service applies the final ordering across the merged set.
        try await fetch(query: query, sinceYear: since.map(Self.year(of:)), limit: limit)
    }

    private func fetch(query: String, sinceYear: Int?, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }

        let cappedLimit = max(1, min(limit, 100))
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ScholarlyError.invalidURL
        }
        var urlString = "\(Self.endpoint)?query=\(encoded)&limit=\(cappedLimit)&fields=\(Self.fields)"
        if let sinceYear { urlString += "&year=\(sinceYear)-" }
        guard let url = URL(string: urlString) else { throw ScholarlyError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholarlyError.http(status: -1) }
        guard (200...299).contains(http.statusCode) else { throw ScholarlyError.http(status: http.statusCode) }
        return try Self.parse(data)
    }

    /// Calendar year of a date in GMT (for Semantic Scholar's `year` filter).
    static func year(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? .current
        return calendar.component(.year, from: date)
    }

    /// Decode a Semantic Scholar `/paper/search` response into PaperHits.
    /// Pure & synchronous — unit-testable against a fixture.
    static func parse(_ data: Data) throws -> [PaperHit] {
        let decoded: S2Response
        do {
            decoded = try JSONDecoder().decode(S2Response.self, from: data)
        } catch {
            throw ScholarlyError.decoding(error.localizedDescription)
        }
        return (decoded.data ?? []).compactMap { $0.toHit() }
    }

    // MARK: - Wire format

    private struct S2Response: Decodable {
        let data: [S2Paper]?
    }

    private struct S2Paper: Decodable {
        let title: String?
        let abstract: String?
        let year: Int?
        let venue: String?
        let citationCount: Int?
        let url: String?
        let externalIds: [String: FlexibleString]?
        let openAccessPdf: S2PDF?
        let authors: [S2Author]?

        func toHit() -> PaperHit? {
            guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let cleanVenue = (venue?.isEmpty == false) ? venue : nil
            return PaperHit(
                title: title,
                authors: (authors ?? []).compactMap { $0.name },
                abstract: abstract ?? "",
                year: year,
                venue: cleanVenue,
                doi: externalIds?["DOI"]?.value,
                arxivId: externalIds?["ArXiv"]?.value,
                url: url,
                pdfURL: openAccessPdf?.url,
                citationCount: citationCount,
                sources: [ScholarlyProviderID.semanticScholar.rawValue]
            )
        }
    }

    private struct S2PDF: Decodable {
        let url: String?
    }

    private struct S2Author: Decodable {
        let name: String?
    }

    /// Semantic Scholar's `externalIds` mixes string ids (DOI, ArXiv, PubMed)
    /// with numeric ones (CorpusId), so decode each value tolerantly.
    private struct FlexibleString: Decodable {
        let value: String?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else if let int = try? container.decode(Int.self) {
                value = String(int)
            } else if let double = try? container.decode(Double.self) {
                value = String(double)
            } else {
                value = nil
            }
        }
    }
}
