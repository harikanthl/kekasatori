//
//  ResearchTaxonomy.swift
//  MuseDrop
//
//  Task taxonomy DTOs for the Discover pillar. A bundled snapshot of research
//  areas → tasks gives the Discover screen a browsable spine (no network) for
//  seeding literature searches. Mirrors the Papers With Code "tasks" page
//  (6 areas, 74 tasks) with snapshot paper counts.
//

import Foundation

/// Discover field: which corpus the cockpit is pointed at. AI uses arXiv +
/// HuggingFace; Medicine uses bioRxiv/medRxiv. OpenAlex + Semantic Scholar span
/// both.
enum ResearchField: String, CaseIterable, Identifiable, Sendable {
    case ai
    case maths
    case physics
    case chemistry
    case medicine

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ai:        return "AI"
        case .maths:     return "Maths"
        case .physics:   return "Physics"
        case .chemistry: return "Chemistry"
        case .medicine:  return "Medicine"
        }
    }
    var symbol: String {
        switch self {
        case .ai:        return "cpu"
        case .maths:     return "x.squareroot"
        case .physics:   return "atom"
        case .chemistry: return "testtube.2"
        case .medicine:  return "cross.case"
        }
    }
    /// OpenAlex concept for an unscoped "Most Cited" (no domain selected).
    var defaultConcept: String? {
        switch self {
        case .ai:        return nil            // broad "machine learning" search
        case .maths:     return "C33923547"    // Mathematics (level 0)
        case .physics:   return "C121332964"   // Physics
        case .chemistry: return "C185592680"   // Chemistry
        case .medicine:  return "C71924100"    // Medicine
        }
    }
    /// Text anchor for the all-domains Most-Cited when no concept applies.
    var mostCitedAnchor: String {
        switch self {
        case .ai:        return "machine learning"
        case .maths:     return "mathematics"
        case .physics:   return "physics"
        case .chemistry: return "chemistry"
        case .medicine:  return "medicine"
        }
    }
    /// arXiv categories for the all-domains Newest feed (empty = not arXiv-based).
    var defaultArxivCategories: [String] {
        switch self {
        case .ai:        return ["cs.LG", "cs.AI", "cs.CL", "cs.CV", "cs.RO", "cs.NE", "stat.ML"]
        case .maths:     return ["math.AG", "math.NT", "math.AP", "math.PR", "math.CO", "math.DG", "math.NA", "math.OC"]
        case .physics:   return ["astro-ph.CO", "cond-mat.str-el", "hep-th", "hep-ph", "quant-ph", "gr-qc", "physics.optics"]
        case .chemistry: return ["physics.chem-ph", "cond-mat.mtrl-sci", "cond-mat.soft"]
        case .medicine:  return []             // bioRxiv/medRxiv, not arXiv
        }
    }

    /// Keyword-search backends for this field's Ask/browse. Semantic Scholar &
    /// OpenAlex span all fields; arXiv covers AI/maths/physics/chem preprints;
    /// Europe PMC is biomedical; GitHub (code) spans every field; HuggingFace
    /// papers are ML-centric, so AI-only.
    var providers: [ScholarlyProviderID] {
        switch self {
        case .ai:
            return [.semanticScholar, .arxiv, .openAlex, .huggingFace, .github]
        case .maths, .physics, .chemistry:
            return [.semanticScholar, .arxiv, .openAlex, .github]
        case .medicine:
            return [.semanticScholar, .openAlex, .europePmc, .github]
        }
    }
}

/// A top-level research area (e.g. Vision) and its tasks. Doubles as a Discover
/// "domain" filter for the trending feed.
struct ResearchArea: Identifiable, Codable, Sendable, Hashable {
    let id: String        // stable slug
    let name: String
    let symbol: String    // SF Symbol name
    let blurb: String
    /// Total papers across the area, at snapshot time.
    var paperCount: Int? = nil
    /// arXiv categories for the Newest feed when this domain is selected.
    var arxivCategories: [String]? = nil
    /// Broad search anchor for the Most-Cited (OpenAlex) feed in this domain.
    var searchAnchor: String? = nil
    /// OpenAlex concept id (e.g. "C31972630") — a precise Most-Cited filter,
    /// preferred over the text anchor when present.
    var openAlexConcept: String? = nil
    /// bioRxiv/medRxiv category keywords for the Medicine Newest feed.
    var preprintCategories: [String]? = nil
    let tasks: [ResearchTask]
}

/// A concrete task within an area. `searchQuery` seeds a scholarly search,
/// falling back to the task name when no explicit query is given.
struct ResearchTask: Identifiable, Codable, Sendable, Hashable {
    let name: String
    /// Papers tagged with this task, at snapshot time.
    var paperCount: Int? = nil
    /// Optional override; many task names are already good queries.
    var query: String? = nil

    var id: String { name }

    var searchQuery: String {
        if let query, !query.isEmpty { return query }
        return name
    }
}
