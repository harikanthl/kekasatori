//
//  ArticleExtractor.swift
//  MuseDrop
//
//  Lightweight HTML readability: pulls a clean title + body text from a web page
//  and discovers same-origin chapter links for multi-chapter books/docs sites.
//  No dependencies; heuristic but robust for article/blog/book pages.
//

import Foundation

enum ArticleExtractor {
    struct Article {
        let title: String
        let text: String
    }

    /// Extract a readable title + body from raw HTML.
    static func extract(html: String) -> Article {
        let title = extractTitle(html)
        let region = mainContentRegion(html)
        let text = htmlToText(region)
        return Article(title: title.isEmpty ? "Web Article" : title, text: text)
    }

    /// Same-origin links under the landing page's directory, in document order —
    /// used to detect and crawl a book/docs site's chapters.
    static func chapterLinks(html: String, base: URL) -> [URL] {
        guard let host = base.host else { return [] }
        let baseDir = base.deletingLastPathComponent().path
        let prefix = baseDir.isEmpty ? "/" : baseDir
        let basePage = canonical(base.absoluteString)

        var seen = Set<String>()
        var result: [URL] = []
        let skipExt: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "css", "js", "zip", "pdf", "xml", "json"]

        for href in captures(#"<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']"#, in: html) {
            guard let abs = URL(string: href, relativeTo: base)?.absoluteURL,
                  let scheme = abs.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  abs.host == host else { continue }
            guard abs.path.hasPrefix(prefix) else { continue }
            if skipExt.contains(abs.pathExtension.lowercased()) { continue }
            let key = canonical(abs.absoluteString)
            if key == basePage || seen.contains(key) { continue }
            seen.insert(key)
            if let url = URL(string: key) { result.append(url) }
            if result.count >= 60 { break }
        }
        return result
    }

    // MARK: - Title

    private static func extractTitle(_ html: String) -> String {
        if let og = firstCapture(#"(?i)<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#, html) {
            return decodeEntities(og)
        }
        if let t = firstCapture(#"(?is)<title[^>]*>(.*?)</title>"#, html) {
            return decodeEntities(collapse(t))
        }
        if let h1 = firstCapture(#"(?is)<h1[^>]*>(.*?)</h1>"#, html) {
            return htmlToText(h1)
        }
        return ""
    }

    // MARK: - Body

    private static func mainContentRegion(_ html: String) -> String {
        for tag in ["article", "main"] {
            if let region = firstCapture("(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)>", html), region.count > 400 {
                return region
            }
        }
        if let body = firstCapture(#"(?is)<body\b[^>]*>(.*?)</body>"#, html) {
            return body
        }
        return html
    }

    private static func htmlToText(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "nav", "header", "footer", "aside", "form", "noscript", "svg", "figure"] {
            s = replace("(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", in: s, with: " ")
        }
        s = replace("(?s)<!--.*?-->", in: s, with: " ")
        // Block-level tags become line breaks so paragraphs survive.
        s = replace(#"(?i)<(/?)(p|div|br|li|h[1-6]|tr|section|blockquote|pre|ul|ol|table)[^>]*>"#, in: s, with: "\n")
        s = replace("(?s)<[^>]+>", in: s, with: " ")
        s = decodeEntities(s)
        s = replace(#"[ \t\u{00A0}]+"#, in: s, with: " ")
        s = replace(#"[ \t]*\n[ \t]*"#, in: s, with: "\n")
        s = replace(#"\n{3,}"#, in: s, with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Entities

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "ldquo": "“", "rdquo": "”", "copy": "©", "reg": "®", "trade": "™",
        "deg": "°", "times": "×", "divide": "÷", "lt;": "<", "rarr": "→", "larr": "←"
    ]

    private static func decodeEntities(_ input: String) -> String {
        var s = input
        // Numeric entities (decimal + hex).
        s = replaceMatches(#"&#x([0-9A-Fa-f]+);"#, in: s) { hex in
            UInt32(hex, radix: 16).flatMap(UnicodeScalar.init).map(String.init) ?? ""
        }
        s = replaceMatches(#"&#([0-9]+);"#, in: s) { dec in
            UInt32(dec).flatMap(UnicodeScalar.init).map(String.init) ?? ""
        }
        for (name, value) in namedEntities {
            s = s.replacingOccurrences(of: "&\(name);", with: value)
        }
        return s
    }

    // MARK: - Regex helpers

    private static func canonical(_ urlString: String) -> String {
        let noFragment = urlString.split(separator: "#", maxSplits: 1).first.map(String.init) ?? urlString
        return noFragment.hasSuffix("/") ? String(noFragment.dropLast()) : noFragment
    }

    private static func collapse(_ s: String) -> String {
        replace(#"\s+"#, in: s, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(_ pattern: String, _ text: String) -> String? {
        captures(pattern, in: text).first
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replace(_ pattern: String, in text: String, with replacement: String, literal: Bool) -> String {
        replace(pattern, in: text, with: NSRegularExpression.escapedTemplate(for: replacement))
    }

    private static func replaceMatches(_ pattern: String, in text: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            result += transform(ns.substring(with: match.range(at: 1)))
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }
}
