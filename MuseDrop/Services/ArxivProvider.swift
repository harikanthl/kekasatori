//
//  ArxivProvider.swift
//  MuseDrop
//
//  ScholarlyProvider backed by the arXiv Atom API. The feed is XML, so parsing
//  uses a small XMLParser delegate; `parse` is pure (no network) for testing.
//
//  Follows the arXiv API user manual:
//  - Multi-word queries are split into terms ANDed in the `all:` field
//    (`all:foo+AND+all:bar`); the prefix only scopes one word otherwise.
//  - Requests are serialized through a shared 3-second rate limiter — the
//    manual asks callers to "play nice and incorporate a 3 second delay",
//    and DeepResearchAgent fans several queries out at once.
//  - Sends an explicit sort and a descriptive User-Agent.
//  https://info.arxiv.org/help/api/user-manual.html
//

import Foundation

struct ArxivProvider: ScholarlyProvider {
    let id: ScholarlyProviderID = .arxiv

    private static let endpoint = "https://export.arxiv.org/api/query"

    /// Shared across calls so concurrent queries are spaced ≥3s apart, per the
    /// arXiv API politeness guidance.
    private static let limiter = ArxivRateLimiter(minInterval: 3)

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Kekasatori/\(version) (macOS; mailto:harikanth.ai@gmail.com)"
    }()

    func search(_ query: String, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }
        return try await execute(searchQuery: Self.buildSearchQuery(trimmed),
                                 sortBy: "relevance", limit: limit)
    }

    func search(_ query: String, sort: PaperSort, since: Date?, limit: Int) async throws -> [PaperHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ScholarlyError.invalidQuery }
        var searchQuery = Self.buildSearchQuery(trimmed)
        if let since {
            searchQuery += "+AND+submittedDate:%5B\(Self.arxivDate(since))+TO+\(Self.arxivDate(Date()))%5D"
        }
        // arXiv has no citation data, so "most cited" can't sort server-side;
        // newest sorts by submission, everything else by relevance.
        let sortBy = (sort == .newest) ? "submittedDate" : "relevance"
        return try await execute(searchQuery: searchQuery, sortBy: sortBy, limit: limit)
    }

    /// Core ML categories used when no specific domain is selected.
    static let coreMLCategories = ["cs.LG", "cs.AI", "cs.CL", "cs.CV", "cs.RO", "cs.NE", "stat.ML"]

    /// Recent submissions newest first for the Trending "Newest" feed, scoped to
    /// `categories`. `since` bounds the submission window (nil = none).
    func fetchRecent(categories: [String], since: Date?, limit: Int) async throws -> [PaperHit] {
        let cats = categories.isEmpty ? Self.coreMLCategories : categories
        var searchQuery = "%28" + cats.map { "cat:\($0)" }.joined(separator: "+OR+") + "%29"
        if let since {
            searchQuery += "+AND+submittedDate:%5B\(Self.arxivDate(since))+TO+\(Self.arxivDate(Date()))%5D"
        }
        return try await execute(searchQuery: searchQuery, sortBy: "submittedDate", limit: limit)
    }

    /// Shared request path: build the URL, respect the rate limit, fetch, parse.
    private func execute(searchQuery: String, sortBy: String, limit: Int) async throws -> [PaperHit] {
        let cappedLimit = max(1, min(limit, 100))   // well under the API's 2000/call ceiling
        guard let url = URL(string:
            "\(Self.endpoint)?search_query=\(searchQuery)"
            + "&start=0&max_results=\(cappedLimit)"
            + "&sortBy=\(sortBy)&sortOrder=descending") else {
            throw ScholarlyError.invalidURL
        }

        // Respect arXiv's requested spacing between successive calls.
        await Self.limiter.waitForSlot()

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ScholarlyError.http(status: -1) }
        guard (200...299).contains(http.statusCode) else { throw ScholarlyError.http(status: http.statusCode) }
        return Self.parse(data)
    }

    /// `yyyyMMddHHmm` in GMT, the format arXiv `submittedDate` ranges expect.
    static func arxivDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.string(from: date)
    }

    /// Build a well-formed `search_query` value. Each whitespace-delimited term
    /// is scoped to `all:` and ANDed, with terms percent-encoded so punctuation
    /// (e.g. `sim-to-real`) can't break the URL. Boolean operators / separators
    /// (`+AND+`, `:`) are intentionally left literal.
    static func buildSearchQuery(_ raw: String) -> String {
        let terms = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        let encoded = terms.compactMap { term -> String? in
            guard let e = term.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  !e.isEmpty else { return nil }
            return "all:" + e
        }
        guard !encoded.isEmpty else {
            // Degenerate input (all punctuation) — fall back to a raw all: query.
            return "all:" + (raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? raw)
        }
        return encoded.joined(separator: "+AND+")
    }

    /// Parse an arXiv Atom feed into PaperHits. Pure & synchronous.
    static func parse(_ data: Data) -> [PaperHit] {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.hits
    }

    /// Extract the bare arXiv id (e.g. `1706.03762v5`) from an abs/pdf URL.
    static func extractArxivId(_ url: String) -> String? {
        guard let range = url.range(of: "/abs/") else { return nil }
        let id = String(url[range.upperBound...])
        return id.isEmpty ? nil : id
    }

    // MARK: - Atom feed parsing

    private final class FeedDelegate: NSObject, XMLParserDelegate {
        var hits: [PaperHit] = []

        private var inEntry = false
        private var inAuthor = false
        private var text = ""

        // current entry accumulators
        private var entryTitle = ""
        private var summary = ""
        private var authors: [String] = []
        private var authorName = ""
        private var idURL = ""
        private var doi: String?
        private var pdfURL: String?
        private var published = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            text = ""
            switch elementName {
            case "entry":
                inEntry = true
                entryTitle = ""; summary = ""; authors = []; idURL = ""
                doi = nil; pdfURL = nil; published = ""
            case "author" where inEntry:
                inAuthor = true; authorName = ""
            case "link" where inEntry:
                if attributeDict["title"] == "pdf" || attributeDict["type"] == "application/pdf" {
                    pdfURL = attributeDict["href"]
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "name" where inAuthor:
                authorName = value
            case "author" where inEntry:
                if !authorName.isEmpty { authors.append(authorName) }
                inAuthor = false
            case "title" where inEntry:
                entryTitle = Self.collapse(value)
            case "summary" where inEntry:
                summary = Self.collapse(value)
            case "id" where inEntry:
                idURL = value
            case "published" where inEntry:
                published = value
            case "arxiv:doi" where inEntry:
                doi = value.isEmpty ? nil : value
            case "entry":
                inEntry = false
                hits.append(makeHit())
            default:
                break
            }
            text = ""
        }

        private func makeHit() -> PaperHit {
            PaperHit(
                title: entryTitle,
                authors: authors,
                abstract: summary,
                year: Int(published.prefix(4)),
                venue: nil,
                doi: doi,
                arxivId: ArxivProvider.extractArxivId(idURL),
                url: idURL.isEmpty ? nil : idURL,
                pdfURL: pdfURL,
                citationCount: nil,
                sources: [ScholarlyProviderID.arxiv.rawValue]
            )
        }

        private static func collapse(_ raw: String) -> String {
            raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
    }
}

/// Serializes outbound arXiv requests so successive calls are spaced at least
/// `minInterval` apart, honoring the API's politeness guidance. The next slot is
/// reserved synchronously before awaiting, so it stays correct under actor
/// reentrancy (several concurrent callers each get a distinct slot).
actor ArxivRateLimiter {
    private let minInterval: TimeInterval
    private var nextAvailable: Date = .distantPast

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    func waitForSlot() async {
        let now = Date()
        let slot = max(now, nextAvailable)
        nextAvailable = slot.addingTimeInterval(minInterval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
