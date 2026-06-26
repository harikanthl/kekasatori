//
//  LocalStubCommunityService.swift
//  MuseDrop
//
//  A fully local stand-in for the discovery wall so the entire publish →
//  discover → import UX is real and testable before the Nostr/IPFS backend
//  exists. The "index" is a JSON file and "seeding" copies the `.kekapack` into
//  a local packs folder. Same protocol the networked backend will implement.
//

import Foundation

actor LocalStubCommunityService: CommunityService {
    private let fileManager = FileManager.default

    func publish(_ draft: CommunityPostDraft) async throws -> CommunityPost {
        try fileManager.createDirectory(at: PathUtils.communityPacksDirectory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let storedPack = PathUtils.communityPacksDirectory.appendingPathComponent("\(id).kekapack")
        if fileManager.fileExists(atPath: storedPack.path) {
            try fileManager.removeItem(at: storedPack)
        }
        try fileManager.copyItem(at: draft.packFileURL, to: storedPack)

        let post = CommunityPost(
            id: id,
            contentType: draft.contentType,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: draft.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: Self.normalize(draft.tags),
            author: draft.author,
            createdAt: Date(),
            upvotes: 0,
            contentRef: .localFile(path: storedPack.path),
            category: draft.category,
            communityId: draft.communityId
        )

        var posts = loadIndex()
        posts.insert(post, at: 0)
        try saveIndex(posts)
        return post
    }

    func posts(matching query: CommunityQuery) async throws -> [CommunityPost] {
        var result = loadIndex()

        if let type = query.contentType {
            result = result.filter { $0.contentType == type }
        }
        if let category = query.category {
            result = result.filter { $0.category == category }
        }
        if let communityId = query.communityId {
            result = result.filter { $0.communityId == communityId }
        }

        let wanted = Set(Self.normalize(query.tags))
        if !wanted.isEmpty {
            result = result.filter { !wanted.isDisjoint(with: $0.tags) }
        }

        let text = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !text.isEmpty {
            result = result.filter { post in
                post.title.lowercased().contains(text)
                    || post.summary.lowercased().contains(text)
                    || post.author.handle.lowercased().contains(text)
                    || post.tags.contains { $0.contains(text) }
            }
        }

        result.sort { $0.createdAt > $1.createdAt }
        return Array(result.prefix(query.limit))
    }

    func fetchPack(for post: CommunityPost) async throws -> URL {
        switch post.contentRef {
        case .localFile(let path):
            let url = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: url.path) else { throw CommunityError.packUnavailable }
            return url
        case .ipfs:
            throw CommunityError.notImplemented
        }
    }

    @discardableResult
    func upvote(postId: String) async throws -> CommunityPost? {
        var posts = loadIndex()
        guard let index = posts.firstIndex(where: { $0.id == postId }) else { return nil }
        posts[index].upvotes += 1
        try saveIndex(posts)
        return posts[index]
    }

    // MARK: - Communities

    func communities() async throws -> [Community] {
        guard let data = try? Data(contentsOf: PathUtils.communityDirectory.appendingPathComponent("communities.json")),
              let list = try? Self.decoder.decode([Community].self, from: data) else {
            return []
        }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    func createCommunity(name: String, summary: String) async throws -> Community {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let community = Community(
            id: UUID().uuidString,
            name: trimmed,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            creator: CommunityIdentity.shared.author,
            createdAt: Date()
        )
        var list = (try? await communities()) ?? []
        list.insert(community, at: 0)
        try fileManager.createDirectory(at: PathUtils.communityDirectory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(list)
        try data.write(to: PathUtils.communityDirectory.appendingPathComponent("communities.json"), options: .atomic)
        return community
    }

    // MARK: - Index I/O

    private func loadIndex() -> [CommunityPost] {
        guard let data = try? Data(contentsOf: PathUtils.communityIndexFile),
              let posts = try? Self.decoder.decode([CommunityPost].self, from: data) else {
            return []
        }
        return posts
    }

    private func saveIndex(_ posts: [CommunityPost]) throws {
        try fileManager.createDirectory(at: PathUtils.communityDirectory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(posts)
        try data.write(to: PathUtils.communityIndexFile, options: .atomic)
    }

    /// Lowercase, hashless, hyphenated, de-duplicated topic tags.
    private static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in tags {
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: " ", with: "-")
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            out.append(tag)
        }
        return out
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
