//
//  HuggingFaceDailyPapersProvider.swift
//  MuseDrop
//
//  Fetches HuggingFace's community-curated "Daily Papers" feed and maps it to
//  PaperHits enriched for the Trending Discover feed (thumbnail, upvotes, GitHub
//  repo + stars). Every paper is an arXiv preprint, so it stays open-access and
//  flows through Add-to-Library + the in-app reader. `parse` is pure for tests.
//
//  API: https://huggingface.co/api/daily_papers
//

import Foundation

struct HuggingFaceDailyPapersProvider: Sendable {
    private static let endpoint = "https://huggingface.co/api/daily_papers"

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Kekasatori/\(version) (macOS; mailto:harikanth.ai@gmail.com)"
    }()

    /// Fetch the current Daily Papers feed, newest/most-upvoted first as returned
    /// by HF. `limit` caps the number of cards.
    func fetch(limit: Int = 40) async throws -> [PaperHit] {
        guard let url = URL(string: Self.endpoint) else { throw ScholarlyError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholarlyError.http(status: -1) }
        guard (200...299).contains(http.statusCode) else { throw ScholarlyError.http(status: http.statusCode) }
        return Array(Self.parse(data).prefix(max(1, limit)))
    }

    /// Parse the Daily Papers JSON into PaperHits. Pure & synchronous.
    static func parse(_ data: Data) -> [PaperHit] {
        guard let items = try? JSONDecoder().decode([DailyItem].self, from: data) else { return [] }
        return items.compactMap { $0.toHit() }
    }

    // MARK: - Decoding

    private struct DailyItem: Decodable {
        let paper: Paper?
        let title: String?
        let summary: String?
        let thumbnail: String?
        let publishedAt: String?
        let numComments: Int?

        struct Paper: Decodable {
            let id: String?
            let title: String?
            let summary: String?
            let authors: [Author]?
            let upvotes: Int?
            let githubRepo: String?
            let githubStars: Int?
            let thumbnail: String?
            let publishedAt: String?

            struct Author: Decodable { let name: String? }
        }

        func toHit() -> PaperHit? {
            // arXiv id is the spine — without it we can't link, import, or dedupe.
            guard let id = paper?.id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else { return nil }

            let title = (paper?.title ?? title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let abstract = (paper?.summary ?? summary ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let authors = (paper?.authors ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
            let dateString = paper?.publishedAt ?? publishedAt ?? ""
            let year = Int(dateString.prefix(4))
            let thumb = paper?.thumbnail ?? thumbnail

            return PaperHit(
                title: collapse(title),
                authors: authors,
                abstract: collapse(abstract),
                year: year,
                venue: "arXiv",
                doi: nil,
                arxivId: id,
                url: "https://arxiv.org/abs/\(id)",
                pdfURL: "https://arxiv.org/pdf/\(id)",
                citationCount: nil,
                sources: [],
                thumbnailURL: thumb,
                upvotes: paper?.upvotes,
                repoURL: paper?.githubRepo,
                stars: paper?.githubStars
            )
        }

        private func collapse(_ raw: String) -> String {
            raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
    }
}
