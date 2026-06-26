//
//  NostrCommunityService.swift
//  MuseDrop
//
//  The real, decentralized discovery wall backed by Nostr (nostr-sdk-ios, pure
//  Swift). A "post" is a signed NIP-78 application-specific event (kind 30078)
//  carrying pack metadata in its JSON content and topic tags as `t` tags,
//  published to public relays. The index is fully decentralized; content bytes
//  are not yet on the wire — that's Phase 3 (IPFS via bundled kubo). Until then a
//  post's `.kekapack` resolves only on the publisher's own machine (deterministic
//  local path); other peers get `packUnavailable` from `fetchPack`. Same protocol
//  as the local stub, so the UI and import paths are unchanged.
//

import Foundation
import Combine
@preconcurrency import NostrSDK

actor NostrCommunityService: CommunityService {
    /// Public relays. A broad spread improves durability — free relays don't
    /// promise to persist our app-specific (kind-30078) events, so the more we
    /// write to, the better the odds at least one keeps each post. A curated
    /// first-party relay (strfry) is the real fix (Phase 4).
    static let defaultRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band",
        "wss://offchain.pub",
        "wss://nostr.mom",
        "wss://relay.snort.social"
    ]

    /// NIP-78 application-specific data. Each post uses a unique `d` tag (its id),
    /// so posts are addressable and never replace one another.
    private static let postKind = 30078
    /// NIP-72 community definition (addressable; `d` = community id).
    private static let communityKind = 34550
    /// Namespacing hashtag so we only read this app's events off shared relays.
    private static let appTag = "kekasatori"
    private static let fetchTimeout: TimeInterval = 8
    private static let connectTimeout: TimeInterval = 4

    private let relays: [String]
    private let fileManager = FileManager.default

    private var pool: RelayPool?
    private var keepaliveTask: Task<Void, Never>?
    /// Fetched events keyed by post id, so `upvote` can react to them.
    private var eventCache: [String: NostrEvent] = [:]

    init(relays: [String] = NostrCommunityService.defaultRelays) {
        self.relays = relays
    }

    // MARK: - Publish

    func publish(_ draft: CommunityPostDraft) async throws -> CommunityPost {
        let postId = UUID().uuidString
        let tags = Self.normalize(draft.tags)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stash the pack at a deterministic local path so the publisher can always
        // re-import their own posts (Phase 3 swaps this for an IPFS CID).
        try fileManager.createDirectory(at: PathUtils.communityPacksDirectory, withIntermediateDirectories: true)
        let storedPack = PathUtils.communityPacksDirectory.appendingPathComponent("\(postId).kekapack")
        if fileManager.fileExists(atPath: storedPack.path) {
            try fileManager.removeItem(at: storedPack)
        }
        try fileManager.copyItem(at: draft.packFileURL, to: storedPack)

        // Add the pack to IPFS so other peers can fetch the bytes. Best-effort:
        // if the node isn't available (offline / download failed) we publish a
        // local-only post exactly as before — the index still goes out over Nostr.
        let ipfsCid = try? await IPFSService.shared.add(storedPack)

        let payload = PostPayload(
            title: title,
            summary: summary,
            handle: draft.author.handle,
            contentType: draft.contentType.rawValue,
            tags: tags,
            ipfsCid: ipfsCid,
            category: draft.category?.rawValue,
            communityId: draft.communityId
        )
        let content = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        var eventTags: [Tag] = []
        if let d = Self.tag(["d", postId]) { eventTags.append(d) }
        if let appHashtag = Self.tag(["t", Self.appTag]) { eventTags.append(appHashtag) }
        for topic in tags {
            if let tag = Self.tag(["t", topic]) { eventTags.append(tag) }
        }
        // Category + community as filterable `t` tags (mirrored in the payload).
        if let category = draft.category, let t = Self.tag(["t", "cat:\(category.rawValue)"]) {
            eventTags.append(t)
        }
        if let communityId = draft.communityId, let t = Self.tag(["t", "comm:\(communityId)"]) {
            eventTags.append(t)
        }

        let event = try NostrEvent.Builder<NostrEvent>(kind: EventKind(rawValue: Self.postKind))
            .content(content)
            .appendTags(contentsOf: eventTags)
            .build(signedBy: CommunityIdentity.shared.keypair)

        let pool = await connectedPool()
        guard pool.relays.contains(where: { $0.state == .connected }) else {
            throw CommunityError.publishFailed
        }
        pool.publishEvent(event)
        eventCache[postId] = event
        saveOwnEvent(event, postId: postId)

        return CommunityPost(
            id: postId,
            contentType: draft.contentType,
            title: title,
            summary: summary,
            tags: tags,
            author: draft.author,
            createdAt: Date(),
            upvotes: 0,
            contentRef: ipfsCid.map { .ipfs(cid: $0) } ?? .localFile(path: storedPack.path),
            category: draft.category,
            communityId: draft.communityId
        )
    }

    // MARK: - Discover

    func posts(matching query: CommunityQuery) async throws -> [CommunityPost] {
        let pool = await connectedPool()

        guard let filter = Filter(
            kinds: [Self.postKind],
            tags: ["t": [Self.appTag]],
            limit: max(query.limit, 1) * 2 // headroom for cross-relay dupes
        ) else { return [] }

        let events = await fetch(filter, from: pool)

        // Decode + de-dupe by post id, keeping the newest version of each.
        var byId: [String: (post: CommunityPost, event: NostrEvent)] = [:]
        for event in events {
            guard let decoded = decode(event) else { continue }
            if let existing = byId[decoded.id], existing.post.createdAt >= decoded.createdAt { continue }
            byId[decoded.id] = (decoded, event)
        }

        eventCache = byId.mapValues { $0.event }

        // Best-effort upvote counts from NIP-25 reactions referencing these events.
        let counts = await reactionCounts(for: byId.values.map { $0.event }, pool: pool)
        var result = byId.map { _, pair -> CommunityPost in
            var post = pair.post
            post.upvotes = counts[pair.event.id] ?? 0
            return post
        }

        // Client-side filtering mirrors the stub's semantics exactly.
        if let type = query.contentType {
            result = result.filter { $0.contentType == type }
        }
        if let category = query.category {
            result = result.filter { $0.category == category }
        }
        // A specific community shows only its posts; nil = the global "Everyone" wall.
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
        case .ipfs(let cid):
            // Fast path: the publisher already has the pack on disk (also seeding it).
            let local = PathUtils.communityPacksDirectory.appendingPathComponent("\(post.id).kekapack")
            if fileManager.fileExists(atPath: local.path) { return local }
            // Otherwise pull the bytes from the IPFS network via the kubo daemon.
            return try await IPFSService.shared.fetch(cid: cid)
        }
    }

    @discardableResult
    func upvote(postId: String) async throws -> CommunityPost? {
        let pool = await connectedPool()

        // Need the underlying event to reference in the reaction. Refresh if absent.
        if eventCache[postId] == nil {
            _ = try? await posts(matching: CommunityQuery())
        }
        guard let event = eventCache[postId] else { return nil }

        // NIP-25 reaction: kind 7, content "+", `e`/`p` tags referencing the post.
        var tags: [Tag] = []
        if let e = Self.tag(["e", event.id]) { tags.append(e) }
        if let p = Self.tag(["p", event.pubkey]) { tags.append(p) }

        let reaction = try NostrEvent.Builder<NostrEvent>(kind: .reaction)
            .content("+")
            .appendTags(contentsOf: tags)
            .build(signedBy: CommunityIdentity.shared.keypair)

        pool.publishEvent(reaction)
        return nil // UI re-fetches; count is authoritative from relays.
    }

    // MARK: - Communities

    func communities() async throws -> [Community] {
        let pool = await connectedPool()
        guard let filter = Filter(kinds: [Self.communityKind], tags: ["t": [Self.appTag]], limit: 200) else {
            return []
        }
        let events = await fetch(filter, from: pool)

        // De-dupe by community id, newest definition wins.
        var byId: [String: Community] = [:]
        for event in events {
            guard let community = decodeCommunity(event) else { continue }
            if let existing = byId[community.id], existing.createdAt >= community.createdAt { continue }
            byId[community.id] = community
        }
        return byId.values.sorted { $0.createdAt > $1.createdAt }
    }

    func createCommunity(name: String, summary: String) async throws -> Community {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CommunityError.publishFailed }

        let communityId = Self.slug(trimmedName) + "-" + UUID().uuidString.prefix(6).lowercased()
        let payload = CommunityPayload(name: trimmedName, summary: trimmedSummary)
        let content = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        var tags: [Tag] = []
        if let d = Self.tag(["d", communityId]) { tags.append(d) }
        if let appHashtag = Self.tag(["t", Self.appTag]) { tags.append(appHashtag) }
        if let nameTag = Self.tag(["name", trimmedName]) { tags.append(nameTag) }

        let event = try NostrEvent.Builder<NostrEvent>(kind: EventKind(rawValue: Self.communityKind))
            .content(content)
            .appendTags(contentsOf: tags)
            .build(signedBy: CommunityIdentity.shared.keypair)

        let pool = await connectedPool()
        guard pool.relays.contains(where: { $0.state == .connected }) else {
            throw CommunityError.publishFailed
        }
        pool.publishEvent(event)
        saveOwnEvent(event, postId: "community-\(communityId)")

        return Community(
            id: communityId,
            name: trimmedName,
            summary: trimmedSummary,
            creator: CommunityIdentity.shared.author,
            createdAt: Date()
        )
    }

    private func decodeCommunity(_ event: NostrEvent) -> Community? {
        guard let id = event.firstValueForTagName(.identifier) else { return nil }
        let payload = try? JSONDecoder().decode(CommunityPayload.self, from: Data(event.content.utf8))
        let name = payload?.name ?? event.firstValueForRawTagName("name") ?? id
        let authorHex = event.pubkey
        return Community(
            id: id,
            name: name,
            summary: payload?.summary ?? "",
            creator: CommunityAuthor(handle: "anon-\(authorHex.suffix(6))", publicKey: authorHex),
            createdAt: Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        )
    }

    // MARK: - Relay lifecycle

    private func connectedPool() async -> RelayPool {
        let pool: RelayPool
        if let existing = self.pool {
            pool = existing
        } else {
            var relaySet = Set<Relay>()
            for urlString in relays {
                if let url = URL(string: urlString), let relay = try? Relay(url: url) {
                    relaySet.insert(relay)
                }
            }
            pool = RelayPool(relays: relaySet)
            self.pool = pool
            startKeepalive()
        }

        // nostr-sdk-ios doesn't auto-reconnect, and relays close idle sockets
        // within seconds — so a cached pool's connections go stale and later
        // fetches fail with "no connection," making posts blink out. Revive any
        // dropped sockets before every use. connect() is a no-op for relays
        // already connected/connecting.
        let wasConnected = pool.relays.contains(where: { $0.state == .connected })
        pool.connect()

        // Wait briefly for at least one live connection.
        let deadline = Date().addingTimeInterval(Self.connectTimeout)
        while Date() < deadline {
            if pool.relays.contains(where: { $0.state == .connected }) { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        // Re-broadcast our own posts on a fresh connect / reconnect (not on every
        // fetch) so they repopulate relays that dropped them, without spamming.
        if !wasConnected {
            Task { await self.republishOwnPosts() }
        }
        return pool
    }

    /// Periodically revive dropped relay sockets (nostr-sdk-ios doesn't
    /// auto-reconnect). Mirrors Damus's `connect_to_disconnected()`. `connect()`
    /// is a no-op for relays that are already connected/connecting, so this only
    /// reconnects the dead ones.
    private func startKeepalive() {
        guard keepaliveTask == nil else { return }
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000) // 12s
                guard let self else { return }
                await self.reviveConnections()
            }
        }
    }

    private func reviveConnections() {
        pool?.connect()
    }

    /// Re-send this user's previously published events to the relays. Public
    /// relays evict our app-specific kind, so without this a post can vanish a
    /// while after it was shared. Resending the *same* signed event keeps its id
    /// and timestamp, so it simply repopulates relays that dropped it.
    private func republishOwnPosts() async {
        guard let pool else { return }
        let dir = PathUtils.communityMyPostsDirectory
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let event = try? JSONDecoder().decode(NostrEvent.self, from: data) {
                pool.publishEvent(event)
            }
        }
    }

    /// Persist a freshly published event so it can be re-broadcast next session.
    private func saveOwnEvent(_ event: NostrEvent, postId: String) {
        let dir = PathUtils.communityMyPostsDirectory
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(event) {
            try? data.write(to: dir.appendingPathComponent("\(postId).json"))
        }
    }

    /// One-shot fetch: subscribe, collect events for `fetchTimeout`, then close.
    /// nostr-sdk-ios has no high-level fetch — it streams via a Combine subject —
    /// so we bridge the subscription into async with a timed collector.
    private func fetch(_ filter: Filter, from pool: RelayPool) async -> [NostrEvent] {
        await withCheckedContinuation { (continuation: CheckedContinuation<[NostrEvent], Never>) in
            let collector = EventCollector()
            let subscriptionId = UUID().uuidString

            collector.cancellable = pool.events
                .filter { $0.subscriptionId == subscriptionId }
                .sink { relayEvent in collector.append(relayEvent.event) }

            _ = pool.subscribe(with: filter, subscriptionId: subscriptionId)

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.fetchTimeout) {
                collector.cancellable?.cancel()
                pool.closeSubscription(with: subscriptionId)
                continuation.resume(returning: collector.drain())
            }
        }
    }

    // MARK: - Reactions

    private func reactionCounts(for events: [NostrEvent], pool: RelayPool) async -> [String: Int] {
        let ids = events.map { $0.id }
        guard !ids.isEmpty, let filter = Filter(kinds: [EventKind.reaction.rawValue], events: ids, limit: 1000) else {
            return [:]
        }

        let reactions = await fetch(filter, from: pool)
        let wanted = Set(ids)

        // Count distinct reacting pubkeys per event (one upvote per person).
        var reactors: [String: Set<String>] = [:]
        for reaction in reactions {
            // The last referenced `e` tag is the reacted-to event (NIP-25).
            if let referenced = reaction.referencedEventIds.last(where: { wanted.contains($0) }) {
                reactors[referenced, default: []].insert(reaction.pubkey)
            }
        }
        return reactors.mapValues { $0.count }
    }

    // MARK: - Decoding

    private func decode(_ event: NostrEvent) -> CommunityPost? {
        let postId = event.firstValueForTagName(.identifier) ?? event.id

        guard let payload = try? JSONDecoder().decode(PostPayload.self, from: Data(event.content.utf8)) else {
            return nil
        }
        let contentType = CommunityContentType(rawValue: payload.contentType) ?? .studyPack
        let authorHex = event.pubkey
        let handle = payload.handle.isEmpty ? "anon-\(authorHex.suffix(6))" : payload.handle

        let contentRef: ContentRef
        if let cid = payload.ipfsCid, !cid.isEmpty {
            contentRef = .ipfs(cid: cid)
        } else {
            let local = PathUtils.communityPacksDirectory.appendingPathComponent("\(postId).kekapack")
            contentRef = .localFile(path: local.path)
        }

        let topicTags = payload.tags.isEmpty
            ? event.allValues(forTagName: .hashtag).filter { $0 != Self.appTag }
            : payload.tags

        return CommunityPost(
            id: postId,
            contentType: contentType,
            title: payload.title,
            summary: payload.summary,
            tags: topicTags,
            author: CommunityAuthor(handle: handle, publicKey: authorHex),
            createdAt: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
            upvotes: 0,
            contentRef: contentRef,
            category: payload.category.flatMap(StudyCategory.init(rawValue:)),
            communityId: payload.communityId
        )
    }

    // MARK: - Helpers

    /// On-wire post metadata carried in the event's JSON content.
    private struct PostPayload: Codable {
        var v: Int = 1
        var title: String
        var summary: String
        var handle: String
        var contentType: String
        var tags: [String]
        var ipfsCid: String?
        var category: String?
        var communityId: String?
    }

    /// On-wire community-definition metadata (NIP-72 kind-34550 content).
    private struct CommunityPayload: Codable {
        var name: String
        var summary: String
    }

    /// A short, URL-ish slug from a community name (ascii alphanumerics + hyphens).
    private static func slug(_ name: String) -> String {
        let mapped = name.lowercased().map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" }
        var slug = String(mapped)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "community" : String(slug.prefix(40))
    }

    /// Build a `Tag` from its raw string-array form via the SDK's public Codable
    /// path (the direct `Tag(name:value:)` initializer is not public in 0.3.0).
    private static func tag(_ parts: [String]) -> Tag? {
        guard let data = try? JSONEncoder().encode(parts) else { return nil }
        return try? JSONDecoder().decode(Tag.self, from: data)
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
            guard !tag.isEmpty, tag != appTag, !seen.contains(tag) else { continue }
            seen.insert(tag)
            out.append(tag)
        }
        return out
    }
}

/// Thread-safe sink target for the Combine-based fetch bridge. The `events`
/// subject delivers on the relays' websocket queues, so collection is locked.
private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [NostrEvent] = []
    var cancellable: AnyCancellable?

    func append(_ event: NostrEvent) {
        lock.lock(); events.append(event); lock.unlock()
    }

    func drain() -> [NostrEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}
