//
//  PlaylistImportService.swift
//  MuseDrop
//
//  Enumerates a YouTube playlist with the bundled yt-dlp (no YouTube Data API /
//  quota needed). `--flat-playlist -J` lists every entry without downloading;
//  the PlaylistImportViewModel then adds each as a stream-only library item and
//  transcribes them one by one. Calls go through YTDlpProcessGate so they don't
//  compete with playback/transcription for the same YouTube session.
//

import Foundation

struct PlaylistEntry: Sendable, Identifiable {
    let id: String          // YouTube video id
    let title: String
    let durationSeconds: Double?
    var watchURL: String { "https://www.youtube.com/watch?v=\(id)" }
}

struct PlaylistInfo: Sendable {
    let title: String
    let entries: [PlaylistEntry]
}

enum PlaylistImportError: LocalizedError {
    case ytDlpMissing
    case enumerationFailed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .ytDlpMissing:
            return "The yt-dlp helper isn't available yet. Open Settings to let it install, then try again."
        case .enumerationFailed(let detail):
            return "Couldn't read the playlist: \(detail)"
        case .empty:
            return "No videos found in this playlist (it may be private or empty)."
        }
    }
}

enum PlaylistImportService {
    /// List a playlist's videos via yt-dlp, newest-first as YouTube returns them.
    /// `max` caps very large playlists.
    static func enumerate(playlistURL: String, max: Int = 300) async throws -> PlaylistInfo {
        guard let ytDlp = PathUtils.getYtDlpPath() else { throw PlaylistImportError.ytDlpMissing }

        let result = try await YTDlpProcessGate.shared.run {
            try await ProcessRunner().run(
                executable: ytDlp,
                arguments: ["--flat-playlist", "-J", "--no-warnings", playlistURL],
                timeout: 90
            )
        }

        guard result.exitCode == 0, let data = result.stdout.data(using: .utf8) else {
            let detail = result.stderr.isEmpty ? "yt-dlp exited \(result.exitCode)" : result.stderr
            throw PlaylistImportError.enumerationFailed(String(detail.prefix(200)))
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaylistImportError.enumerationFailed("unreadable response")
        }

        let title = (root["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Playlist"
        let rawEntries = (root["entries"] as? [[String: Any]]) ?? []

        var entries: [PlaylistEntry] = []
        for entry in rawEntries.prefix(max) {
            guard let id = entry["id"] as? String, !id.isEmpty else { continue }
            let entryTitle = (entry["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
            let duration = (entry["duration"] as? Double) ?? (entry["duration"] as? NSNumber)?.doubleValue
            entries.append(PlaylistEntry(id: id, title: entryTitle, durationSeconds: duration))
        }

        guard !entries.isEmpty else { throw PlaylistImportError.empty }
        return PlaylistInfo(title: title, entries: entries)
    }
}
