//
//  TrendingFeedService.swift
//  MuseDrop
//
//  Backs the Trending half of Discover. Three lenses over the live literature:
//  Trending (HuggingFace daily papers), Newest (arXiv recent submissions), and
//  Most Cited (OpenAlex, citation-ranked) — each over a time window. Returns the
//  shared PaperHit so feed cards reuse Add-to-Library, OA tags, and the reader.
//

import Foundation

/// The three lenses, each with the time windows that make sense for it.
enum TrendingTab: String, CaseIterable, Identifiable, Sendable {
    case trending
    case newest
    case mostCited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending:  return "Trending"
        case .newest:    return "Newest"
        case .mostCited: return "Most Cited"
        }
    }

    /// Time ranges this lens supports. Citation ranking needs time to accrue, so
    /// Most Cited skips short windows; HF "trending" is inherently today's feed.
    var supportedRanges: [TrendingTimeRange] {
        switch self {
        case .trending:  return [.today]
        case .newest:    return [.today, .week, .month, .year]
        case .mostCited: return [.week, .month, .year, .allTime]
        }
    }

    var defaultRange: TrendingTimeRange { supportedRanges.first ?? .allTime }

    /// Tabs available for a field. HuggingFace's daily feed is AI-only, so
    /// Medicine drops the Trending tab.
    static func tabs(for field: ResearchField) -> [TrendingTab] {
        // HuggingFace's daily feed is AI-only; every other field is preprints + citations.
        switch field {
        case .ai: return [.trending, .newest, .mostCited]
        default:  return [.newest, .mostCited]
        }
    }
}

enum TrendingTimeRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case year
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:   return "Today"
        case .week:    return "This Week"
        case .month:   return "This Month"
        case .year:    return "This Year"
        case .allTime: return "All Time"
        }
    }

    /// Time ranges offered when browsing a topic (Today is too narrow for a
    /// keyword search, so it starts at this week).
    static let browseRanges: [TrendingTimeRange] = [.allTime, .year, .month, .week]

    /// Lower bound of the window, or nil for all time.
    var since: Date? {
        let day: TimeInterval = 86_400
        switch self {
        case .today:   return Date().addingTimeInterval(-day)
        case .week:    return Date().addingTimeInterval(-7 * day)
        case .month:   return Date().addingTimeInterval(-30 * day)
        case .year:    return Date().addingTimeInterval(-365 * day)
        case .allTime: return nil
        }
    }
}

struct TrendingFeedService: Sendable {
    static let shared = TrendingFeedService()

    func load(field: ResearchField = .ai,
              tab: TrendingTab,
              range: TrendingTimeRange,
              domain: ResearchArea? = nil,
              limit: Int = 40) async throws -> [PaperHit] {
        switch tab {
        case .trending:
            // HuggingFace's daily feed isn't domain-queryable; show it whole.
            return try await HuggingFaceDailyPapersProvider().fetch(limit: limit)
        case .newest:
            if field == .medicine {
                return try await BioRxivProvider().fetchRecent(
                    categories: domain?.preprintCategories ?? [], since: range.since, limit: limit)
            }
            let categories = domain?.arxivCategories ?? field.defaultArxivCategories
            return try await ArxivProvider().fetchRecent(
                categories: categories, since: range.since, limit: limit)
        case .mostCited:
            // A domain's own concept is most precise; else fall back to a domain
            // text anchor, and to the field concept only when no domain is picked.
            let concept = domain?.openAlexConcept ?? (domain == nil ? field.defaultConcept : nil)
            let anchor = domain?.searchAnchor ?? field.mostCitedAnchor
            return try await OpenAlexProvider().mostCited(
                search: anchor, concept: concept, since: range.since, limit: limit)
        }
    }

    /// Whether a tab respects the domain filter (HuggingFace trending does not).
    static func tabSupportsDomain(_ tab: TrendingTab) -> Bool { tab != .trending }
}
