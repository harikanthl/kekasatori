//
//  HuggingFaceProvider.swift
//  MuseDrop
//
//  ScholarlyProvider backed by HuggingFace's papers search — a first-class
//  Discover source (distinct from the curated Daily Papers *trending* feed).
//  Hybrid semantic + full-text search over title/authors/content. Every HF paper
//  is an arXiv preprint, so hits carry an arxivId and dedupe/merge cleanly with
//  the arXiv / OpenAlex results (sources unioned), while adding upvotes,
//  thumbnails and linked GitHub repos.
//
//  API: GET https://huggingface.co/api/papers/search?q={q}&limit={n}  (n 1–120)
//  Optional `Authorization: Bearer <hf token>` lifts the rate limit.
//

import Foundation

struct HuggingFaceProvider: ScholarlyProvider {
    let id: ScholarlyProviderID = .huggingFace

    private static let endpoint = "https://huggingface.co/api/papers/search"

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Kekasatori/\(version) (macOS; mailto:harikanth.ai@gmail.com)"
    }()

    func search(_ query: String, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }

        let cappedLimit = max(1, min(limit, 120))
        guard let q = String(trimmed.prefix(250))
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.endpoint)?q=\(q)&limit=\(cappedLimit)") else {
            throw ScholarlyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainService.get(KeychainService.Account.huggingFace), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholarlyError.http(status: -1) }
        guard (200...299).contains(http.statusCode) else { throw ScholarlyError.http(status: http.statusCode) }
        return Self.parse(data)
    }

    // HF search has no sort/time parameters; the default protocol implementation
    // routes sort/since variants here. (ScholarlySearchService re-sorts the merged
    // set by the chosen lens anyway.)

    /// Parse the papers/search JSON into PaperHits. Pure & synchronous.
    static func parse(_ data: Data) -> [PaperHit] {
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return items.compactMap { $0.toHit() }
    }

    // MARK: - Decoding (lenient — mirrors the Daily Papers item shape)

    private struct Item: Decodable {
        let paper: Paper?
        let title: String?
        let summary: String?
        let thumbnail: String?
        let publishedAt: String?

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
                sources: [ScholarlyProviderID.huggingFace.rawValue],
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
