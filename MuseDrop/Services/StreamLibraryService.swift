//
//  StreamLibraryService.swift
//  MuseDrop
//

import Foundation

enum StreamLibraryError: LocalizedError {
    case invalidURL
    case resolutionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Please enter a valid URL."
        case .resolutionFailed(let message):
            return message
        }
    }
}

@MainActor
final class StreamLibraryService {
    static let shared = StreamLibraryService()
    
    private let resolver = StreamResolverService.shared
    private let libraryManager = LibraryManager.shared
    private let logService = LogService.shared
    
    private init() {}
    
    func addStreamItem(
        url: String,
        kind: StreamMediaKind,
        playlistId: UUID? = nil,
        playlistTitle: String? = nil
    ) async throws -> DownloadItem {
        guard URL(string: url) != nil else {
            throw StreamLibraryError.invalidURL
        }

        logService.info("Adding stream item (\(kind.rawValue)): \(url)")

        let metadata = try await resolver.fetchMetadata(for: url)
        let itemId = UUID()
        let thumbnail = await resolver.downloadThumbnail(metadata, itemId: itemId)

        // Defer playback URL resolution until player opens (reduces rate limiting).
        let item = DownloadItem(
            id: itemId,
            url: url,
            title: metadata.title,
            thumbnail: thumbnail,
            format: kind == .audio ? "stream-audio" : "stream-video",
            progress: 1.0,
            status: .completed,
            outputPath: nil,
            summaryExists: false,
            consumptionMode: .streamOnly,
            streamURL: nil,
            streamExpiresAt: nil,
            streamMediaKind: kind,
            durationSeconds: metadata.durationSeconds > 0 ? metadata.durationSeconds : nil,
            playlistId: playlistId,
            playlistTitle: playlistTitle
        )
        
        libraryManager.addDownload(item)
        logService.info("Stream bookmark saved: \(metadata.title)")
        return item
    }
    
    func refreshStreamURL(
        for item: DownloadItem,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> DownloadItem {
        invalidatePersistedPlayback(for: item)
        guard item.isStreamOnly, let kind = item.streamMediaKind else {
            return item
        }
        
        let resolved = try await resolver.resolvePlaybackURL(
            for: item.url,
            kind: kind,
            forceRefresh: true,
            onProgress: onProgress
        )
        
        var updated = item
        updated.streamURL = resolved.playbackURL
        updated.streamExpiresAt = resolved.expiresAt
        libraryManager.updateDownload(updated)
        return updated
    }
    
    /// Clears persisted and in-memory playback URLs so the next open re-resolves.
    func invalidatePersistedPlayback(for item: DownloadItem) {
        resolver.invalidatePlaybackCache(for: item.url)
        guard item.isStreamOnly else { return }
        var cleared = item
        cleared.streamURL = nil
        cleared.streamExpiresAt = nil
        libraryManager.updateDownload(cleared)
    }
    
    func playbackItem(
        for item: DownloadItem,
        forceRefresh: Bool = false,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> DownloadItem {
        guard item.isStreamOnly, let kind = item.streamMediaKind else {
            return item
        }
        
        if !forceRefresh,
           let streamURL = item.streamURL,
           let expiresAt = item.streamExpiresAt,
           !item.streamURLIsExpired {
            resolver.seedMemoryCache(
                sourceURL: item.url,
                kind: kind,
                playbackURL: streamURL,
                expiresAt: expiresAt
            )
            return item
        }
        
        let resolved = try await resolver.resolvePlaybackURL(
            for: item.url,
            kind: kind,
            forceRefresh: forceRefresh,
            onProgress: onProgress
        )
        var updated = item
        updated.streamURL = resolved.playbackURL
        updated.streamExpiresAt = resolved.expiresAt
        libraryManager.updateDownload(updated)
        return updated
    }
}
