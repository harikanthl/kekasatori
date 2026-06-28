//
//  BioRxivProvider.swift
//  MuseDrop
//
//  Recent preprints from bioRxiv + medRxiv for the Medicine field's "Newest"
//  feed. The details API is date-range based (no keyword search), so this only
//  powers the trending feed, not browse. Every preprint is open-access, so its
//  PDF flows through Add-to-Library + the reader. `parse` is pure for tests.
//
//  API: https://api.biorxiv.org/details/{server}/{start}/{end}/{cursor}
//

import Foundation

struct BioRxivProvider: Sendable {
    /// Pull recent preprints across both servers, optionally keeping only the
    /// given bioRxiv/medRxiv categories (case-insensitive substring match).
    func fetchRecent(categories: [String], since: Date?, limit: Int) async throws -> [PaperHit] {
        let end = Date()
        let start = since ?? end.addingTimeInterval(-30 * 86_400)
        let startStr = Self.dateString(start)
        let endStr = Self.dateString(end)

        var hits: [PaperHit] = []
        for server in ["biorxiv", "medrxiv"] {
            // Two cursor pages (60 papers) per server is plenty for the feed.
            for cursor in [0, 30] {
                guard let url = URL(string: "https://api.biorxiv.org/details/\(server)/\(startStr)/\(endStr)/\(cursor)") else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    break   // stop paging this server on error
                }
                let page = Self.parse(data)
                hits.append(contentsOf: page)
                if page.count < 30 { break }   // last page
            }
        }

        let filtered = Self.filter(hits, categories: categories)
        // Newest first (ISO date strings sort lexicographically); cap.
        let sorted = filtered.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        return Array(PaperHit.merge(sorted).prefix(max(1, limit)))
    }

    /// Keep hits whose venue/category contains any keyword (empty = keep all).
    static func filter(_ hits: [PaperHit], categories: [String]) -> [PaperHit] {
        guard !categories.isEmpty else { return hits }
        let needles = categories.map { $0.lowercased() }
        return hits.filter { hit in
            let hay = (hit.venue ?? "").lowercased()
            return needles.contains { hay.contains($0) }
        }
    }

    /// Parse a bioRxiv/medRxiv details response into PaperHits. Pure.
    static func parse(_ data: Data) -> [PaperHit] {
        guard let response = try? JSONDecoder().decode(DetailsResponse.self, from: data) else { return [] }
        return (response.collection ?? []).compactMap { $0.toHit() }
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Wire format

    private struct DetailsResponse: Decodable {
        let collection: [Preprint]?
    }

    private struct Preprint: Decodable {
        let title: String?
        let authors: String?
        let doi: String?
        let date: String?
        let version: String?
        let category: String?
        let abstract: String?
        let server: String?

        func toHit() -> PaperHit? {
            guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let doi, !doi.isEmpty else { return nil }

            let serverName = (server?.lowercased() == "medrxiv") ? "medRxiv" : "bioRxiv"
            let host = (server?.lowercased() == "medrxiv") ? "www.medrxiv.org" : "www.biorxiv.org"
            let versioned = (version.map { "v\($0)" }) ?? ""
            let landing = "https://\(host)/content/\(doi)\(versioned)"
            let pdf = "https://\(host)/content/\(doi)\(versioned).full.pdf"
            let venue = category.map { "\(serverName) · \($0)" } ?? serverName

            return PaperHit(
                title: title,
                authors: Self.parseAuthors(authors),
                abstract: abstract?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                year: date.flatMap { Int($0.prefix(4)) },
                venue: venue,
                doi: doi,
                arxivId: nil,
                url: landing,
                pdfURL: pdf,
                citationCount: nil,
                sources: []
            )
        }

        /// Authors arrive as "Last, F.; Other, A. B.; …".
        static func parseAuthors(_ raw: String?) -> [String] {
            guard let raw, !raw.isEmpty else { return [] }
            return raw.split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }
}
