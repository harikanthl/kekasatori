//
//  PaperDetailService.swift
//  MuseDrop
//
//  Backing data for the Papers-with-Code-style paper detail page:
//    1. an AI-generated TL;DR sentence distilled from the abstract,
//    2. a BibTeX entry synthesized from the hit's fields, and
//    3. related papers fetched by title from the scholarly providers.
//  Tasks and Methods are NOT here — they're detected from the title + abstract
//  against the controlled vocabularies in TasksCatalog / MethodsCatalog, so they
//  stay canonical and work with no AI provider. Everything degrades gracefully:
//  no provider → no TL;DR, no network → no related papers, but the page still
//  renders from `PaperHit` (plus the offline catalog tags) alone.
//

import Foundation

enum PaperDetailService {

    // MARK: - AI TL;DR

    /// A single plain-language sentence summarizing the paper, grounded only in
    /// its title and abstract. Returns nil when no AI provider is configured or
    /// there's no abstract to read — the section then simply doesn't render.
    static func tldr(for hit: PaperHit,
                     settings: LLMProviderSettings = .load()) async -> String? {
        guard LLMRouter.shared.resolveRoute(settings: settings) != .unavailable else { return nil }
        let abstract = hit.abstract.trimmingCharacters(in: .whitespacesAndNewlines)
        guard abstract.count >= 40 else { return nil }

        let system = LLMMessage(.system, """
        You write a one-sentence TL;DR of a research paper for a busy reader. Using \
        ONLY the title and abstract, reply with a SINGLE plain-language sentence of \
        at most 40 words stating the key idea or result. No preamble, no markdown, \
        no quotes — just the sentence. Never invent benchmark names or numbers.
        """)
        let user = LLMMessage(.user, "Title: \(hit.title)\n\nAbstract: \(abstract)")

        do {
            let stream = await LLMRouter.shared.stream(messages: [system, user], settings: settings)
            var raw = ""
            for try await delta in stream { raw += delta }
            return clean(raw)
        } catch {
            return nil
        }
    }

    /// Trim whitespace, strip wrapping quotes / a leading "TL;DR:" label, and drop
    /// to nil if the model returned nothing usable.
    static func clean(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["TL;DR:", "TL;DR", "Summary:"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.count >= 2, text.first == "\"", text.last == "\"" {
            text = String(text.dropFirst().dropLast())
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Citation

    /// A BibTeX entry built from the hit's fields. Always available — an arXiv
    /// preprint becomes `@misc` with an eprint, anything else `@article`.
    static func bibtex(for hit: PaperHit) -> String {
        let lastName = hit.authors.first?
            .split(separator: " ").last.map(String.init) ?? "unknown"
        let yearKey = hit.year.map(String.init) ?? "nd"
        let titleWord = hit.title.split(separator: " ").first.map(String.init) ?? "paper"
        let key = (lastName + yearKey + titleWord)
            .lowercased().filter { $0.isLetter || $0.isNumber }

        let isArxiv = !(hit.arxivId ?? "").isEmpty
        var fields: [(String, String)] = [("title", hit.title)]
        if !hit.authors.isEmpty { fields.append(("author", hit.authors.joined(separator: " and "))) }
        if let year = hit.year { fields.append(("year", String(year))) }
        if isArxiv {
            fields.append(("eprint", PaperHit.normalizedArxivId(hit.arxivId!)))
            fields.append(("archivePrefix", "arXiv"))
        } else if let venue = hit.venue, !venue.isEmpty {
            fields.append(("journal", venue))
        }
        if let doi = hit.doi, !doi.isEmpty { fields.append(("doi", doi)) }
        if let url = hit.externalURLString { fields.append(("url", url)) }

        let body = fields
            .map { "  \($0.0.padding(toLength: 14, withPad: " ", startingAt: 0))= {\($0.1)}" }
            .joined(separator: ",\n")
        return "@\(isArxiv ? "misc" : "article"){\(key),\n\(body)\n}"
    }

    // MARK: - Related papers

    /// Papers related by title, via Semantic Scholar + arXiv. The hit itself is
    /// filtered out. Empty on any failure — the section just doesn't render.
    static func related(to hit: PaperHit, limit: Int = 6) async -> [PaperHit] {
        let query = hit.title.split(whereSeparator: { $0.isWhitespace })
            .prefix(12).joined(separator: " ")
        guard query.count >= 4 else { return [] }

        let service = ScholarlySearchService(enabled: [.semanticScholar, .arxiv])
        let hits = await service.search(query, limitPerProvider: 10)
        return Array(hits.filter { $0.id != hit.id }.prefix(limit))
    }

    // MARK: - External links

    /// Hugging Face papers page for an arXiv preprint, when we have an arXiv id.
    static func huggingFaceURL(for hit: PaperHit) -> URL? {
        guard let arxivId = hit.arxivId, !arxivId.isEmpty else { return nil }
        return URL(string: "https://huggingface.co/papers/\(PaperHit.normalizedArxivId(arxivId))")
    }

    /// Best PDF link: the provider's direct PDF, else arXiv's `/pdf/` endpoint.
    static func pdfURL(for hit: PaperHit) -> URL? {
        if let pdf = hit.pdfURL, let url = URL(string: pdf) { return url }
        if let arxivId = hit.arxivId, !arxivId.isEmpty {
            return URL(string: "https://arxiv.org/pdf/\(PaperHit.normalizedArxivId(arxivId))")
        }
        return nil
    }

    /// Best abstract/landing link: the provider's URL, else arXiv's `/abs/`.
    static func abstractPageURL(for hit: PaperHit) -> URL? {
        if let url = hit.url, let parsed = URL(string: url) { return parsed }
        if let arxivId = hit.arxivId, !arxivId.isEmpty {
            return URL(string: "https://arxiv.org/abs/\(PaperHit.normalizedArxivId(arxivId))")
        }
        if let ext = hit.externalURLString { return URL(string: ext) }
        return nil
    }
}
