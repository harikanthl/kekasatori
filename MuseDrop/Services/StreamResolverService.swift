//
//  StreamResolverService.swift
//  MuseDrop
//
//  Playback: AVPlayer plays HLS (.m3u8) or a single muxed URL directly — no ffmpeg.
//  See yt-dlp docs: --print manifest_url for adaptive HLS; avoid bv*+ba --get-url
//  which returns separate DASH streams AVPlayer cannot play together.
//

import Foundation

enum StreamResolverError: LocalizedError {
    case ytDlpNotFound
    case invalidURL
    case metadataFailed(String)
    case streamURLFailed(String)
    case invalidStreamURL
    
    var errorDescription: String? {
        switch self {
        case .ytDlpNotFound:
            return "yt-dlp not found. Restart the app to restore bundled binaries."
        case .invalidURL:
            return "Invalid media URL."
        case .metadataFailed(let message):
            return "Failed to read media info: \(message)"
        case .streamURLFailed(let message):
            return "Failed to resolve stream: \(message)"
        case .invalidStreamURL:
            return "Could not get a playable stream URL."
        }
    }
}

@MainActor
final class StreamResolverService {
    static let shared = StreamResolverService()
    
    private let logService = LogService.shared
    private let streamTTL: TimeInterval = 3 * 60 * 60
    
    private var memoryCache: [String: ResolvedStream] = [:]
    private static let resolveTimeout: TimeInterval = 25
    private static let maxCacheEntries = 32
    
    private init() {}
    
    func fetchMetadata(for sourceURL: String) async throws -> StreamMetadata {
        let ytDlp = try ytDlpPath()
        
        let (stdout, stderr, code) = try await YTDlpProcessGate.shared.run {
            try await ProcessRunner().run(
                executable: ytDlp,
                arguments: ["-j", "--no-playlist", "--no-warnings", sourceURL],
                timeout: Self.resolveTimeout
            )
        }
        
        guard code == 0 else {
            throw StreamResolverError.metadataFailed(stderr.isEmpty ? stdout : stderr)
        }
        guard let data = stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Process succeeded but its output wasn't valid metadata JSON.
            throw StreamResolverError.metadataFailed("Couldn't read media info from this source.")
        }
        
        let title = json["title"] as? String ?? "Untitled"
        let duration = (json["duration"] as? Double) ?? (json["duration"] as? Int).map(Double.init) ?? 0
        let uploader = json["uploader"] as? String ?? json["channel"] as? String ?? ""
        let extractor = json["extractor"] as? String ?? "unknown"
        
        var thumbnailURL: URL?
        if let thumb = json["thumbnail"] as? String {
            thumbnailURL = URL(string: thumb)
        }
        
        return StreamMetadata(
            title: title,
            thumbnailURL: thumbnailURL,
            durationSeconds: duration,
            uploader: uploader,
            extractor: extractor
        )
    }
    
    func resolvePlaybackURL(
        for sourceURL: String,
        kind: StreamMediaKind,
        forceRefresh: Bool = false,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> ResolvedStream {
        let cacheKey = "\(sourceURL)|\(kind.rawValue)"
        
        if !forceRefresh, let cached = memoryCache[cacheKey], cached.expiresAt > Date() {
            return cached
        }
        
        pruneExpiredCacheEntries()
        let ytDlp = try ytDlpPath()
        let clientProfiles = youtubeClientProfiles(for: sourceURL)
        let maxHeight = Self.preferredMaxHeight()
        let muxedFormat = kind == .video
            ? Self.muxedVideoFormat(maxHeight: maxHeight)
            : "ba/b"

        // Muxed (progressive) MP4 on YouTube tops out at 720p — and is usually
        // only 360p (format 18). So when the user wants more than 720p we resolve
        // the HLS manifest first: AVPlayer plays it natively and adapts up to
        // 1080p+. For 720p-and-below, muxed is faster and stays within the cap.
        let preferHLS = kind == .video && (maxHeight == nil || maxHeight! > 720)

        for (index, extraArgs) in clientProfiles.enumerated() {
            let profileLabel = index == 0 ? "default" : "fallback \(index)"
            onProgress?("Resolving stream (\(profileLabel))…")

            if preferHLS,
               let hls = try await resolveHLSManifest(
                sourceURL: sourceURL,
                ytDlp: ytDlp,
                extraArgs: extraArgs,
                maxHeight: maxHeight
               ) {
                return cacheResolved(hls, cacheKey: cacheKey, label: "HLS manifest")
            }

            if let url = try await resolveSingleStreamURL(
                sourceURL: sourceURL,
                ytDlp: ytDlp,
                format: muxedFormat,
                extraArgs: extraArgs
            ) {
                return cacheResolved(url, cacheKey: cacheKey, label: kind == .video ? "muxed MP4" : "audio")
            }

            if kind == .video, !preferHLS,
               let hls = try await resolveHLSManifest(
                sourceURL: sourceURL,
                ytDlp: ytDlp,
                extraArgs: extraArgs,
                maxHeight: maxHeight
               ) {
                return cacheResolved(hls, cacheKey: cacheKey, label: "HLS manifest")
            }
        }
        
        throw StreamResolverError.invalidStreamURL
    }
    
    func invalidateCache(for sourceURL: String) {
        memoryCache = memoryCache.filter { !$0.key.hasPrefix(sourceURL) }
    }
    
    /// Clears cached playback URLs so the next open re-resolves (e.g. after AVPlayer failure).
    func invalidatePlaybackCache(for sourceURL: String) {
        invalidateCache(for: sourceURL)
    }
    
    /// Align in-memory cache with a persisted library stream URL.
    func seedMemoryCache(
        sourceURL: String,
        kind: StreamMediaKind,
        playbackURL: URL,
        expiresAt: Date
    ) {
        guard expiresAt > Date() else { return }
        let cacheKey = "\(sourceURL)|\(kind.rawValue)"
        memoryCache[cacheKey] = ResolvedStream(playbackURL: playbackURL, expiresAt: expiresAt)
    }
    
    func downloadThumbnail(_ metadata: StreamMetadata, itemId: UUID) async -> URL? {
        guard let remoteURL = metadata.thumbnailURL else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try FileUtils.createDirectory(at: PathUtils.coversDirectory)
            let localURL = PathUtils.coversDirectory.appendingPathComponent("\(itemId.uuidString).jpg")
            try data.write(to: localURL)
            return localURL
        } catch {
            logService.warning("Thumbnail download failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private
    
    /// Max video height the user selected in Settings, or nil for "Best Available".
    static func preferredMaxHeight() -> Int? {
        switch UserDefaults.standard.string(forKey: "defaultVideoResolution") {
        case "1080p": return 1080
        case "720p": return 720
        case "480p": return 480
        default: return nil
        }
    }

    /// Muxed (progressive) MP4 selector, capped to the preferred height.
    private static func muxedVideoFormat(maxHeight: Int?) -> String {
        if let h = maxHeight {
            return "b[ext=mp4][height<=\(h)][acodec!=none][vcodec!=none]/best[height<=\(min(h, 720))][ext=mp4][acodec!=none]/18/b"
        }
        return "b[ext=mp4][acodec!=none][vcodec!=none]/best[ext=mp4][acodec!=none]/22/18/b"
    }

    private func resolveHLSManifest(
        sourceURL: String,
        ytDlp: URL,
        extraArgs: [String],
        maxHeight: Int?
    ) async throws -> URL? {
        // YouTube HLS variants: 94≈480p, 95≈720p, 96≈1080p. Prefer a height-
        // capped selection, then fall back to the generic HLS master.
        let formats: [String]
        switch maxHeight {
        case .some(let h) where h <= 480:
            formats = ["best[height<=480][protocol*=m3u8]", "94/best[protocol*=m3u8]"]
        case .some(let h) where h <= 720:
            formats = ["best[height<=720][protocol*=m3u8]", "95/94/best[protocol*=m3u8]"]
        case .some(let h):
            formats = ["best[height<=\(h)][protocol*=m3u8]", "96/95/94/best[protocol*=m3u8]"]
        case .none:
            formats = ["best[protocol*=m3u8]", "96/95/94/best[protocol*=m3u8]"]
        }
        for format in formats {
            guard let manifest = try? await printField(
                "manifest_url",
                sourceURL: sourceURL,
                ytDlp: ytDlp,
                format: format,
                extraArgs: extraArgs
            ) else { continue }
            
            let trimmed = manifest.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.uppercased() != "NA",
                  let url = parseURL(trimmed),
                  url.absoluteString.localizedCaseInsensitiveContains("m3u8") else {
                continue
            }
            return url
        }
        return nil
    }
    
    private func cacheResolved(_ url: URL, cacheKey: String, label: String) -> ResolvedStream {
        let resolved = ResolvedStream(playbackURL: url, expiresAt: Date().addingTimeInterval(streamTTL))
        memoryCache[cacheKey] = resolved
        pruneExpiredCacheEntries()
        while memoryCache.count > Self.maxCacheEntries {
            guard let oldestKey = memoryCache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key else { break }
            memoryCache.removeValue(forKey: oldestKey)
        }
        logService.info("Resolved stream (\(label)) — expires in \(Int(streamTTL / 3600))h")
        return resolved
    }
    
    private func pruneExpiredCacheEntries() {
        let now = Date()
        memoryCache = memoryCache.filter { $0.value.expiresAt > now }
    }
    
    private func printField(_ field: String, sourceURL: String, ytDlp: URL, format: String, extraArgs: [String] = []) async throws -> String {
        let (stdout, stderr, code) = try await YTDlpProcessGate.shared.run {
            try await ProcessRunner().run(
                executable: ytDlp,
                arguments: extraArgs + [
                    "-f", format,
                    "--print", field,
                    "--no-playlist",
                    "--no-warnings",
                    sourceURL
                ],
                timeout: Self.resolveTimeout
            )
        }
        guard code == 0 else {
            throw StreamResolverError.streamURLFailed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func resolveSingleStreamURL(sourceURL: String, ytDlp: URL, format: String, extraArgs: [String] = []) async throws -> URL? {
        let (stdout, stderr, code) = try await YTDlpProcessGate.shared.run {
            try await ProcessRunner().run(
                executable: ytDlp,
                arguments: extraArgs + [
                    "-f", format,
                    "--get-url",
                    "--no-playlist",
                    "--no-warnings",
                    sourceURL
                ],
                timeout: Self.resolveTimeout
            )
        }
        
        guard code == 0 else {
            let message = stderr.isEmpty ? stdout : stderr
            if message.localizedCaseInsensitiveContains("drm") {
                logService.warning("Skipped DRM-protected format for \(format)")
            } else {
                logService.debug("Format \(format) failed: \(message.prefix(200))")
            }
            return nil
        }
        
        let urls = stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { parseURL($0) }
        
        // Never hand AVPlayer a lone DASH video URL when audio is on a second line.
        if urls.count > 1 {
            if let hls = urls.first(where: { $0.absoluteString.contains("m3u8") }) {
                return hls
            }
            logService.warning("Got \(urls.count) separate stream URLs — skipping (AVPlayer needs one URL or HLS)")
            return nil
        }
        
        return urls.first
    }
    
    private func parseURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http") else { return nil }
        return URL(string: trimmed)
    }
    
    /// yt-dlp client profiles for YouTube. Avoid ios,tv,web — requires PO tokens on 2026.06+.
    private func youtubeClientProfiles(for sourceURL: String) -> [[String]] {
        guard sourceURL.contains("youtube.com") || sourceURL.contains("youtu.be") else {
            return [[]]
        }
        
        return [
            [], // yt-dlp default — fastest reliable path for muxed MP4
            ["--extractor-args", "youtube:player_client=tv,android_sdkless,web"],
        ]
    }
    
    private func ytDlpPath() throws -> URL {
        guard let path = PathUtils.getYtDlpPath() else {
            throw StreamResolverError.ytDlpNotFound
        }
        return path
    }
}
