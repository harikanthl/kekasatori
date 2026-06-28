//
//  EuropePmcProvider.swift
//  MuseDrop
//
//  ScholarlyProvider backed by Europe PMC — a free, keyword-searchable index of
//  biomedical literature (PubMed/MEDLINE + preprints + open-access full text).
//  The Medicine field's search/browse backbone, since bioRxiv/medRxiv expose
//  only a date feed. `parse` is pure for tests.
//
//  API: https://www.ebi.ac.uk/europepmc/webservices/rest/search
//

import Foundation

struct EuropePmcProvider: ScholarlyProvider {
    let id: ScholarlyProviderID = .europePmc

    private static let endpoint = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"

    func search(_ query: String, limit: Int) async throws -> [PaperHit] {
        try await run(query: query, sort: .relevance, since: nil, limit: limit)
    }

    func search(_ query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit] {
        try await run(query: query, sort: sort, since: since, limit: limit)
    }

    private func run(query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }

        var queryExpr = trimmed
        if let since {
            queryExpr += " AND (PUB_YEAR:[\(Self.year(of: since)) TO 3000])"
        }

        var components = URLComponents(string: Self.endpoint)
        var items = [
            URLQueryItem(name: "query", value: queryExpr),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "resultType", value: "core"),
            URLQueryItem(name: "pageSize", value: String(max(1, min(limit, 100))))
        ]
        switch sort {
        case .newest:    items.append(URLQueryItem(name: "sort", value: "P_PDATE_D desc"))
        case .mostCited: items.append(URLQueryItem(name: "sort", value: "CITED desc"))
        case .relevance: break
        }
        components?.queryItems = items
        guard let url = components?.url else { throw ScholarlyError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholarlyError.http(status: -1) }
        guard (200...299).contains(http.statusCode) else { throw ScholarlyError.http(status: http.statusCode) }
        return Self.parse(data)
    }

    /// Decode a Europe PMC search response into PaperHits. Pure & synchronous.
    static func parse(_ data: Data) -> [PaperHit] {
        guard let response = try? JSONDecoder().decode(EPMCResponse.self, from: data) else { return [] }
        return (response.resultList?.result ?? []).compactMap { $0.toHit() }
    }

    static func year(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? .current
        return calendar.component(.year, from: date)
    }

    // MARK: - Wire format

    private struct EPMCResponse: Decodable {
        let resultList: ResultList?
        struct ResultList: Decodable { let result: [Result]? }
    }

    private struct Result: Decodable {
        let title: String?
        let authorString: String?
        let abstractText: String?
        let pubYear: String?
        let doi: String?
        let citedByCount: Int?
        let journalInfo: JournalInfo?
        let fullTextUrlList: FullTextUrlList?

        struct JournalInfo: Decodable { let journal: Journal?; struct Journal: Decodable { let title: String? } }
        struct FullTextUrlList: Decodable { let fullTextUrl: [FullTextUrl]? }
        struct FullTextUrl: Decodable {
            let documentStyle: String?
            let availability: String?
            let url: String?
        }

        func toHit() -> PaperHit? {
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let urls = fullTextUrlList?.fullTextUrl ?? []
            let pdf = urls.first { ($0.documentStyle ?? "").lowercased() == "pdf" }?.url
            let landing = urls.first { ($0.documentStyle ?? "").lowercased() == "html" }?.url
                ?? urls.first?.url
                ?? doi.map { "https://doi.org/\($0)" }

            return PaperHit(
                title: title,
                authors: Self.parseAuthors(authorString),
                abstract: abstractText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                year: pubYear.flatMap { Int($0) },
                venue: journalInfo?.journal?.title,
                doi: doi,
                arxivId: nil,
                url: landing,
                pdfURL: pdf,
                citationCount: citedByCount,
                sources: [ScholarlyProviderID.europePmc.rawValue]
            )
        }

        /// Author strings arrive comma-separated: "Cohn DM, Gurugama P, …".
        static func parseAuthors(_ raw: String?) -> [String] {
            guard let raw, !raw.isEmpty else { return [] }
            return raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}
