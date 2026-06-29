//
//  GitHubProvider.swift
//  MuseDrop
//
//  ScholarlyProvider backed by GitHub's repository search — surfaces code
//  implementations alongside papers in Discover. Repos have no DOI/arXiv id, so
//  they're not open-access (no in-app reader / Add-to-Library) but expose a repo
//  link + star count and "Open page". Keyed by repo URL in dedupe so a repo can't
//  collapse into a same-named paper.
//
//  API: GET https://api.github.com/search/repositories?q={q}&sort=stars&order=desc
//  Optional `Authorization: Bearer <token>` lifts the search rate limit (10→30/min).
//

import Foundation

struct GitHubProvider: ScholarlyProvider {
    let id: ScholarlyProviderID = .github

    private static let endpoint = "https://api.github.com/search/repositories"

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Kekasatori/\(version) (macOS; mailto:harikanth.ai@gmail.com)"
    }()

    func search(_ query: String, limit: Int) async throws -> [PaperHit] {
        try await execute(query: query, sort: "stars", since: nil, limit: limit)
    }

    func search(_ query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit] {
        // GitHub can't rank by citations; "most cited" maps to stars (the default),
        // "newest" to most-recently-pushed.
        let ghSort = (sort == .newest) ? "updated" : "stars"
        return try await execute(query: query, sort: ghSort, since: since, limit: limit)
    }

    private func execute(query: String, sort: String, since: Date?, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }

        var qualifiers = trimmed
        if let since { qualifiers += " pushed:>=\(Self.day(since))" }

        let cappedLimit = max(1, min(limit, 50))
        guard let q = qualifiers.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "\(Self.endpoint)?q=\(q)&sort=\(sort)&order=desc&per_page=\(cappedLimit)") else {
            throw ScholarlyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token = KeychainService.get(KeychainService.Account.githubToken), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholarlyError.http(status: -1) }
        guard (200...299).contains(http.statusCode) else { throw ScholarlyError.http(status: http.statusCode) }
        return Self.parse(data)
    }

    /// `yyyy-MM-dd` in GMT, the format GitHub date qualifiers expect.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Parse the repository-search JSON into PaperHits. Pure & synchronous.
    static func parse(_ data: Data) -> [PaperHit] {
        guard let result = try? JSONDecoder().decode(SearchResult.self, from: data) else { return [] }
        return result.items.compactMap { $0.toHit() }
    }

    // MARK: - Decoding

    private struct SearchResult: Decodable {
        let items: [Repo]
    }

    private struct Repo: Decodable {
        let fullName: String?
        let name: String?
        let description: String?
        let htmlURL: String?
        let stargazersCount: Int?
        let language: String?
        let pushedAt: String?
        let owner: Owner?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case name
            case description
            case htmlURL = "html_url"
            case stargazersCount = "stargazers_count"
            case language
            case pushedAt = "pushed_at"
            case owner
        }

        struct Owner: Decodable { let login: String? }

        func toHit() -> PaperHit? {
            let title = (fullName ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let link = htmlURL, !link.isEmpty else { return nil }

            var blurb = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let language, !language.isEmpty {
                blurb = blurb.isEmpty ? language : "\(blurb)  ·  \(language)"
            }

            return PaperHit(
                title: title,
                authors: [owner?.login].compactMap { $0 },
                abstract: blurb,
                year: Int((pushedAt ?? "").prefix(4)),
                venue: "GitHub",
                doi: nil,
                arxivId: nil,
                url: link,
                pdfURL: nil,
                citationCount: nil,
                sources: [ScholarlyProviderID.github.rawValue],
                repoURL: link,
                stars: stargazersCount
            )
        }
    }
}
