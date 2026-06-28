//
//  BibTeX.swift
//  MuseDrop
//
//  Render DeepResearch citations as a BibTeX bibliography for export into a
//  researcher's reference manager. Pure string building — unit-tested.
//

import Foundation

enum BibTeX {
    /// A BibTeX bibliography for the cited sources, in citation order.
    static func bibliography(_ hits: [PaperHit]) -> String {
        hits.enumerated()
            .map { entry($0.element, fallbackIndex: $0.offset + 1) }
            .joined(separator: "\n\n")
    }

    /// One entry. arXiv preprints render as `@misc` with `eprint`/`archivePrefix`;
    /// everything else as `@article`.
    static func entry(_ hit: PaperHit, fallbackIndex: Int) -> String {
        let isArxiv = !(hit.arxivId ?? "").isEmpty
        let type = isArxiv ? "misc" : "article"
        let key = citationKey(hit, fallbackIndex: fallbackIndex)

        var fields: [(String, String)] = []
        if !hit.authors.isEmpty {
            fields.append(("author", hit.authors.map(clean).joined(separator: " and ")))
        }
        fields.append(("title", clean(hit.title)))
        if let year = hit.year { fields.append(("year", String(year))) }
        if let venue = hit.venue, !venue.isEmpty {
            fields.append((isArxiv ? "howpublished" : "journal", clean(venue)))
        }
        if isArxiv, let id = hit.arxivId {
            fields.append(("eprint", PaperHit.normalizedArxivId(id)))
            fields.append(("archivePrefix", "arXiv"))
        }
        if let doi = hit.doi, !doi.isEmpty { fields.append(("doi", clean(doi))) }
        if let url = hit.externalURLString { fields.append(("url", url)) }

        let body = fields.map { "  \($0.0) = {\($0.1)}" }.joined(separator: ",\n")
        return "@\(type){\(key),\n\(body)\n}"
    }

    /// A citation key like `vaswani2017attention` — first author surname + year +
    /// first meaningful title word. Falls back to `ref{n}` when nothing usable.
    static func citationKey(_ hit: PaperHit, fallbackIndex: Int) -> String {
        let surname = hit.authors.first
            .flatMap { $0.split(separator: " ").last.map(String.init) }
            .map { asciiAlnum($0).lowercased() } ?? ""
        let year = hit.year.map(String.init) ?? ""
        let word = hit.title.split(separator: " ")
            .lazy
            .map { asciiAlnum(String($0)).lowercased() }
            .first(where: { $0.count > 2 }) ?? ""
        // Fall back to a unique ref{n} only when nothing usable exists — a bare
        // "ref" with no index would collide across author-less papers.
        let key = surname + year + word
        return key.isEmpty ? "ref\(fallbackIndex)" : key
    }

    // MARK: - Helpers

    /// Strip braces (BibTeX-significant) and trim; we keep values plain.
    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func asciiAlnum(_ s: String) -> String {
        String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
