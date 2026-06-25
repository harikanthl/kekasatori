//
//  WebSearchService.swift
//  MuseDrop
//
//  Lightweight web research for the study agent (DuckDuckGo instant answers).
//

import Foundation

struct WebSearchResult: Identifiable, Codable, Hashable {
    var id: String { url.isEmpty ? title : url }
    var title: String
    var snippet: String
    var url: String
}

enum WebSearchService {
    private static let logService = LogService.shared
    
    static func search(_ query: String, maxResults: Int = 4) async -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_redirect=1&no_html=1&skip_disambig=1") else {
            return []
        }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            return parseInstantAnswerJSON(data, maxResults: maxResults)
        } catch {
            logService.debug("Web search failed for \"\(trimmed)\": \(error.localizedDescription)")
            return []
        }
    }
    
    static func searchTopics(_ topics: [String], maxPerTopic: Int = 2) async -> [WebSearchResult] {
        var combined: [WebSearchResult] = []
        var seen = Set<String>()
        
        for topic in topics.prefix(4) {
            let hits = await search(topic, maxResults: maxPerTopic)
            for hit in hits where seen.insert(hit.id).inserted {
                combined.append(hit)
            }
        }
        return combined
    }
    
    static func formatForPrompt(_ results: [WebSearchResult]) -> String? {
        // These results come from the open web and are untrusted. Sanitize each
        // field, drop entries without a valid http(s) URL, and cap lengths so a
        // crafted snippet cannot smuggle prompt instructions into the model.
        let sanitized: [String] = results.compactMap { result in
            guard let safeURL = sanitizedURL(result.url) else { return nil }
            let title = sanitizeText(result.title, maxChars: maxTitleChars)
            let snippet = sanitizeText(result.snippet, maxChars: maxSnippetChars)
            guard !title.isEmpty || !snippet.isEmpty else { return nil }
            return """
            \(title)
            \(snippet)
            Source: \(safeURL)
            """
        }

        guard !sanitized.isEmpty else { return nil }

        var block = ""
        for (index, entry) in sanitized.enumerated() {
            let next = "[\(index + 1)] \(entry)"
            if block.count + next.count + 2 > maxTotalChars { break }
            block += (block.isEmpty ? "" : "\n\n") + next
        }
        return block.isEmpty ? nil : block
    }

    // MARK: - Sanitization

    private static let maxTitleChars = 160
    private static let maxSnippetChars = 500
    private static let maxTotalChars = 4_000

    /// Strips ASCII control characters and collapses whitespace, then caps length.
    private static func sanitizeText(_ text: String, maxChars: Int) -> String {
        let stripped = String(text.unicodeScalars.filter { scalar in
            // Keep regular tab/newline-stripped content as spaces; drop other
            // C0/C1 control characters that could carry hidden instructions.
            !(scalar.value < 0x20 || (scalar.value >= 0x7F && scalar.value <= 0x9F))
        })
        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxChars else { return collapsed }
        return String(collapsed.prefix(maxChars)) + "…"
    }

    /// Returns the URL string only if it is a well-formed http/https URL.
    private static func sanitizedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Parsing
    
    private static func parseInstantAnswerJSON(_ data: Data, maxResults: Int) -> [WebSearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        var results: [WebSearchResult] = []
        
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
            let title = (json["Heading"] as? String) ?? "Overview"
            let link = (json["AbstractURL"] as? String) ?? ""
            results.append(WebSearchResult(title: title, snippet: abstract, url: link))
        }
        
        if let related = json["RelatedTopics"] as? [[String: Any]] {
            for item in related {
                if let text = item["Text"] as? String, !text.isEmpty {
                    let url = (item["FirstURL"] as? String) ?? ""
                    let title = text.components(separatedBy: " - ").first ?? text
                    let snippet = text.components(separatedBy: " - ").dropFirst().joined(separator: " - ")
                    results.append(WebSearchResult(
                        title: title,
                        snippet: snippet.isEmpty ? text : snippet,
                        url: url
                    ))
                } else if let nested = item["Topics"] as? [[String: Any]] {
                    for sub in nested {
                        guard let text = sub["Text"] as? String, !text.isEmpty else { continue }
                        let url = (sub["FirstURL"] as? String) ?? ""
                        results.append(WebSearchResult(title: text, snippet: text, url: url))
                    }
                }
                if results.count >= maxResults { break }
            }
        }
        
        return Array(results.prefix(maxResults))
    }
}
