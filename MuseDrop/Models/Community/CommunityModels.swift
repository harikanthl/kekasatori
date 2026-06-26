//
//  CommunityModels.swift
//  MuseDrop
//
//  Domain types for the community discovery wall (Phase 2). These are backend-
//  agnostic: a `CommunityPost` describes a shareable artifact and points at its
//  bytes via a `ContentRef`. Today the stub resolves a local file; in Phase 3
//  the same ref becomes an IPFS CID, and posts become signed Nostr events —
//  without these types changing.
//

import Foundation

/// The kind of artifact a post carries. Study packs ship first; `article` is
/// the next planned content type (publishable research notes).
enum CommunityContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case studyPack
    case article

    var id: String { rawValue }

    var label: String {
        switch self {
        case .studyPack: return "Study Pack"
        case .article: return "Article"
        }
    }

    var glyph: String {
        switch self {
        case .studyPack: return "text.book.closed"
        case .article: return "doc.richtext"
        }
    }
}

/// A fixed subject taxonomy for shared packs. Curated (not free-form) so the
/// wall can offer clean category filters; free-form `tags` complement it.
enum StudyCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case math, computerScience, physics, chemistry, biology, medicine
    case engineering, economics, business, socialScience, humanities
    case languages, law, arts, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .math: return "Mathematics"
        case .computerScience: return "Computer Science"
        case .physics: return "Physics"
        case .chemistry: return "Chemistry"
        case .biology: return "Biology"
        case .medicine: return "Medicine"
        case .engineering: return "Engineering"
        case .economics: return "Economics"
        case .business: return "Business"
        case .socialScience: return "Social Science"
        case .humanities: return "Humanities"
        case .languages: return "Languages"
        case .law: return "Law"
        case .arts: return "Arts"
        case .other: return "Other"
        }
    }

    var glyph: String {
        switch self {
        case .math: return "function"
        case .computerScience: return "cpu"
        case .physics: return "atom"
        case .chemistry: return "testtube.2"
        case .biology: return "leaf"
        case .medicine: return "cross.case"
        case .engineering: return "gearshape.2"
        case .economics: return "chart.line.uptrend.xyaxis"
        case .business: return "briefcase"
        case .socialScience: return "person.2"
        case .humanities: return "books.vertical"
        case .languages: return "globe"
        case .law: return "building.columns"
        case .arts: return "paintpalette"
        case .other: return "square.grid.2x2"
        }
    }
}

/// A poster's identity. `publicKey` is a Nostr-style pubkey (hex); a placeholder
/// is generated locally until real Nostr signing lands.
struct CommunityAuthor: Codable, Hashable, Sendable {
    var handle: String
    var publicKey: String
}

/// An open, public community: a named, discoverable space anyone can post into.
/// Defined by a Nostr event; `id` is its addressable `d` identifier.
struct Community: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var summary: String
    var creator: CommunityAuthor
    var createdAt: Date
}

/// Where a post's `.kekapack` bytes can be fetched from.
enum ContentRef: Codable, Hashable, Sendable {
    /// A file in the local published store (stub backend).
    case localFile(path: String)
    /// An IPFS content identifier (Phase 3).
    case ipfs(cid: String)
}

/// One entry on the discovery wall.
struct CommunityPost: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var contentType: CommunityContentType
    var title: String
    var summary: String
    var tags: [String]
    var author: CommunityAuthor
    var createdAt: Date
    var upvotes: Int
    var contentRef: ContentRef
    /// Curated subject (optional for backward compatibility with older posts).
    var category: StudyCategory?
    /// The community this was posted to, or nil for the global "Everyone" wall.
    var communityId: String?
}

/// A new post to publish: metadata plus the `.kekapack` file to share.
struct CommunityPostDraft: Sendable {
    var contentType: CommunityContentType
    var title: String
    var summary: String
    var tags: [String]
    var author: CommunityAuthor
    var packFileURL: URL
    var category: StudyCategory?
    var communityId: String?
}

/// Filters for fetching the wall. Empty fields mean "no filter".
struct CommunityQuery: Sendable {
    var searchText: String = ""
    var tags: [String] = []
    var contentType: CommunityContentType?
    var category: StudyCategory?
    var communityId: String?
    var limit: Int = 200
}
