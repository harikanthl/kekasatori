//
//  CommunityViewModel.swift
//  MuseDrop
//

import Foundation

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published var posts: [CommunityPost] = []
    @Published var communities: [Community] = []
    @Published var searchText = ""
    @Published var selectedType: CommunityContentType?
    @Published var selectedCategory: StudyCategory?
    /// nil = the global "Everyone" wall; otherwise scoped to one community.
    @Published var selectedCommunity: Community?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = CommunityProvider.shared

    func reload() {
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let query = CommunityQuery(
            searchText: searchText,
            contentType: selectedType,
            category: selectedCategory,
            communityId: selectedCommunity?.id
        )
        do {
            async let postsResult = service.posts(matching: query)
            async let communitiesResult = service.communities()
            posts = try await postsResult
            communities = (try? await communitiesResult) ?? communities
            errorMessage = nil
        } catch {
            posts = []
            errorMessage = error.localizedDescription
        }
    }

    /// Create a new community, refresh the list, and switch the wall to it.
    @discardableResult
    func createCommunity(name: String, summary: String) async -> Community? {
        do {
            let community = try await service.createCommunity(name: name, summary: summary)
            communities.insert(community, at: 0)
            selectedCommunity = community
            await load()
            return community
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func upvote(_ post: CommunityPost) {
        // Optimistic bump for instant feedback. The Nostr backend publishes a
        // reaction and returns nil (the authoritative count is relay-side and
        // eventually consistent); the stub returns the updated post to reconcile.
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index].upvotes += 1
        }
        Task {
            let updated = try? await service.upvote(postId: post.id)
            if let updated, let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = updated
            }
        }
    }

    /// Resolve and import a post's pack into the local library.
    func importPost(_ post: CommunityPost) async -> Bool {
        do {
            let url = try await service.fetchPack(for: post)
            let decoded = try StudyPackExporter.readPack(at: url)
            let imported = DataStore.shared.importStudyPack(decoded) != nil
            if let root = decoded.rootDirectory {
                try? FileManager.default.removeItem(at: root)
            }
            if !imported { errorMessage = "Couldn't add this pack to your library." }
            return imported
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
