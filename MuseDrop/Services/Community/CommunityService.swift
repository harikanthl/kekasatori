//
//  CommunityService.swift
//  MuseDrop
//
//  The swappable backend for the discovery wall. Today this is a local stub;
//  Phase 2 swaps in a Nostr-backed index + IPFS content resolution behind the
//  exact same protocol, so the UI and import paths never change.
//

import Foundation

protocol CommunityService: Sendable {
    /// Publish a prepared pack to the wall, returning the created post.
    func publish(_ draft: CommunityPostDraft) async throws -> CommunityPost

    /// Fetch wall entries matching a query (newest first).
    func posts(matching query: CommunityQuery) async throws -> [CommunityPost]

    /// Resolve a post's `.kekapack` bytes to a local file URL for import.
    func fetchPack(for post: CommunityPost) async throws -> URL

    /// Register an upvote and return the updated post (best-effort).
    @discardableResult
    func upvote(postId: String) async throws -> CommunityPost?

    /// Discover open communities (newest first).
    func communities() async throws -> [Community]

    /// Create a new open, public community and return it.
    func createCommunity(name: String, summary: String) async throws -> Community
}

/// The active backend. A single seam to swap implementations. Defaults to the
/// decentralized Nostr index; set `community.useLocalStub` in UserDefaults to
/// fall back to the fully offline stub (useful for tests/dev without a network).
enum CommunityProvider {
    static let shared: any CommunityService = {
        if UserDefaults.standard.bool(forKey: "community.useLocalStub") {
            return LocalStubCommunityService()
        }
        return NostrCommunityService()
    }()
}

enum CommunityError: LocalizedError {
    case packUnavailable
    case notImplemented
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .packUnavailable:
            return "This study pack is no longer available from the sharer."
        case .notImplemented:
            return "Fetching this content from the network isn't available yet."
        case .publishFailed:
            return "Couldn't reach any relay to publish. Check your connection and try again."
        }
    }
}
