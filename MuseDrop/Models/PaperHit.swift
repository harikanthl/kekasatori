//
//  PaperHit.swift
//  MuseDrop
//
//  Normalized scholarly search result, provider-agnostic. Returned by every
//  ScholarlyProvider and merged across providers by ScholarlySearchService.
//  This is the Discover-pillar DTO (Phase 0): no LLM, no network of its own.
//

import Foundation

struct PaperHit: Identifiable, Codable, Sendable {
    var title: String
    var authors: [String]
    var abstract: String
    var year: Int?
    var venue: String?
    var doi: String?
    var arxivId: String?
    /// Landing/abstract page.
    var url: String?
    /// Direct open-access PDF, when the provider exposes one.
    var pdfURL: String?
    var citationCount: Int?
    /// Raw provider ids that surfaced this hit (unioned on dedupe).
    var sources: [String]

    // Trending-feed enrichments (HuggingFace Daily Papers). All nil for plain
    // keyword search; populated only when a paper comes from the trending feed.
    var thumbnailURL: String?
    var upvotes: Int?
    var repoURL: String?
    var stars: Int?

    init(title: String,
         authors: [String] = [],
         abstract: String = "",
         year: Int? = nil,
         venue: String? = nil,
         doi: String? = nil,
         arxivId: String? = nil,
         url: String? = nil,
         pdfURL: String? = nil,
         citationCount: Int? = nil,
         sources: [String] = [],
         thumbnailURL: String? = nil,
         upvotes: Int? = nil,
         repoURL: String? = nil,
         stars: Int? = nil) {
        self.title = title
        self.authors = authors
        self.abstract = abstract
        self.year = year
        self.venue = venue
        self.doi = doi
        self.arxivId = arxivId
        self.url = url
        self.pdfURL = pdfURL
        self.citationCount = citationCount
        self.sources = sources
        self.thumbnailURL = thumbnailURL
        self.upvotes = upvotes
        self.repoURL = repoURL
        self.stars = stars
    }

    /// Stable identity for dedupe & SwiftUI lists: DOI → arXiv id → repo URL
    /// (code results) → normalized title. Derived, never encoded.
    var id: String { Self.dedupeKey(doi: doi, arxivId: arxivId, repoURL: repoURL, title: title) }

    // MARK: - Dedupe / merge

    /// Collapse duplicate hits (same `id`) into one, keeping the richest fields
    /// and unioning sources. Input order is preserved for the survivors.
    static func merge(_ hits: [PaperHit]) -> [PaperHit] {
        // Pass 1: collapse by exact identity (DOI / arXiv id / title).
        var byKey: [String: PaperHit] = [:]
        var order: [String] = []
        for hit in hits {
            let key = hit.id
            if var existing = byKey[key] {
                existing.absorb(hit)
                byKey[key] = existing
            } else {
                byKey[key] = hit
                order.append(key)
            }
        }

        // Pass 2: collapse records that share a title but were kept apart by
        // mismatched identifiers — notably a poisoned metadata record (fake DOI
        // pointing at a junk mirror) vs. the canonical arXiv record. Folding them
        // propagates the arXiv id + a reputable URL onto one survivor and drops
        // the junk duplicate. Guarded on a non-trivial title to avoid collisions.
        var survivorByTitle: [String: String] = [:]
        var dropped = Set<String>()
        for key in order {
            guard let hit = byKey[key] else { continue }
            // Never fold a code result (repo) into a paper by title.
            if key.hasPrefix("repo:") { continue }
            let title = normalizedTitle(hit.title)
            guard title.count > 8 else { continue }
            if let survivorKey = survivorByTitle[title], var survivor = byKey[survivorKey] {
                survivor.absorb(hit)
                byKey[survivorKey] = survivor
                dropped.insert(key)
            } else {
                survivorByTitle[title] = key
            }
        }
        return order.filter { !dropped.contains($0) }.compactMap { byKey[$0] }
    }

    /// Fold another hit (assumed same paper) into this one, filling gaps and
    /// preferring the more complete value.
    mutating func absorb(_ other: PaperHit) {
        if other.abstract.count > abstract.count { abstract = other.abstract }
        if (doi ?? "").isEmpty { doi = other.doi }
        if (arxivId ?? "").isEmpty { arxivId = other.arxivId }
        url = Self.preferredURL(url, other.url)
        pdfURL = Self.preferredURL(pdfURL, other.pdfURL)
        if year == nil { year = other.year }
        if (venue ?? "").isEmpty { venue = other.venue }
        if authors.isEmpty { authors = other.authors }
        citationCount = max(citationCount ?? 0, other.citationCount ?? 0)
        for source in other.sources where !sources.contains(source) {
            sources.append(source)
        }
    }

    // MARK: - Key derivation

    static func dedupeKey(doi: String?, arxivId: String?, repoURL: String? = nil, title: String) -> String {
        if let doi, !doi.isEmpty { return "doi:" + doi.lowercased() }
        if let arxivId, !arxivId.isEmpty { return "arxiv:" + normalizedArxivId(arxivId) }
        // A code result (repo link, no paper id) is keyed by its repo so it stays
        // distinct from a same-named paper rather than collapsing into it.
        if let repoURL, !repoURL.isEmpty { return "repo:" + repoURL.lowercased() }
        return "title:" + normalizedTitle(title)
    }

    /// Lowercased, alphanumerics-only, whitespace-collapsed — tolerant to
    /// punctuation/casing differences between providers.
    static func normalizedTitle(_ raw: String) -> String {
        let scalars = raw.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// Strips an `arxiv:` prefix and any trailing version (`v2`) so 2401.00001
    /// and 2401.00001v3 collapse together.
    static func normalizedArxivId(_ raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("arxiv:") { value.removeFirst("arxiv:".count) }
        if let range = value.range(of: #"v\d+$"#, options: .regularExpression) {
            value.removeSubrange(range)
        }
        return value
    }

    // MARK: - URL trust

    /// Reputable scholarly hosts whose PDF/landing links we'll open directly.
    /// Anything else (e.g. predatory mirrors OpenAlex sometimes ingests, like
    /// `langtaosha.org.cn`) is treated as untrusted and not surfaced as a link.
    private static let trustedHosts: Set<String> = [
        "arxiv.org", "doi.org", "openreview.net", "aclanthology.org", "acm.org",
        "springer.com", "nature.com", "sciencedirect.com", "ieee.org", "nih.gov",
        "europepmc.org", "biorxiv.org", "medrxiv.org", "mlr.press", "nips.cc",
        "neurips.cc", "openalex.org", "semanticscholar.org", "jmlr.org", "aaai.org",
        "mdpi.com", "frontiersin.org", "plos.org", "wiley.com", "tandfonline.com",
        "cell.com", "science.org", "pnas.org", "oup.com", "github.com",
        "huggingface.co", "ssrn.com", "researchsquare.com", "elifesciences.org"
    ]

    /// Whether a URL string points at a known-reputable scholarly host (exact
    /// host or a subdomain of one). Unknown hosts are conservatively untrusted.
    static func isReputableScholarlyHost(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return trustedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Pick the more trustworthy of two URLs: a reputable host beats an unknown
    /// one; otherwise keep the existing value. Empty values defer to the other.
    static func preferredURL(_ current: String?, _ incoming: String?) -> String? {
        let cur = current ?? "", inc = incoming ?? ""
        if cur.isEmpty { return incoming }
        if inc.isEmpty { return current }
        let curTrusted = isReputableScholarlyHost(cur)
        let incTrusted = isReputableScholarlyHost(inc)
        if incTrusted && !curTrusted { return incoming }
        return current
    }
}

extension PaperHit: Hashable {
    // Identity-based: two hits are "equal" when they resolve to the same paper.
    static func == (lhs: PaperHit, rhs: PaperHit) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Access / links

extension PaperHit {
    /// A freely fetchable full text exists — an arXiv preprint or an explicit
    /// open-access PDF. These can be imported and read in-app; gated hits
    /// (publisher landing page only) cannot, so we send those to the browser.
    var isOpenAccess: Bool {
        if let arxivId, !arxivId.isEmpty { return true }
        if let pdfURL, !pdfURL.isEmpty { return true }
        return false
    }

    /// A thumbnail for feed cards: the provider's own, or — for any arXiv paper
    /// — HuggingFace's generated social-card image, so Newest/browse arXiv cards
    /// get art for free. Nil (→ placeholder) only when neither is available.
    var displayThumbnailURL: String? {
        if let thumbnailURL, !thumbnailURL.isEmpty { return thumbnailURL }
        if let arxivId, !arxivId.isEmpty {
            let bare = Self.normalizedArxivId(arxivId)   // strip version suffix
            return "https://cdn-thumbnails.huggingface.co/social-thumbnails/papers/\(bare).png"
        }
        return nil
    }

    /// Best link for opening the source in a browser: landing page → PDF → DOI.
    var externalURLString: String? {
        if let url, !url.isEmpty { return url }
        if let pdfURL, !pdfURL.isEmpty { return pdfURL }
        if let doi, !doi.isEmpty { return "https://doi.org/\(doi)" }
        return nil
    }
}
