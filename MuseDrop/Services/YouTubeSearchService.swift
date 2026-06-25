//
//  YouTubeSearchService.swift
//  Kekasatori
//
//  In-app YouTube search using the bundled yt-dlp (`ytsearch`). No Google API
//  key and no quota — results are extracted directly.
//

import Foundation

struct YouTubeSearchResult: Identifiable, Hashable, Sendable {
    let id: String          // YouTube video id
    let title: String
    let channel: String
    let duration: Double?
    let thumbnailURL: URL?

    var url: String { "https://www.youtube.com/watch?v=\(id)" }

    var durationLabel: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

enum YouTubeSearchError: LocalizedError {
    case binaryMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing: return "The search tool isn't ready yet. Try again in a moment."
        case .failed(let m):  return m
        }
    }
}

actor YouTubeSearchService {
    static let shared = YouTubeSearchService()
    private init() {}

    /// Field separator unlikely to appear in titles/channel names.
    private static let sep = "\u{001F}"

    func search(_ query: String, limit: Int = 15) async throws -> [YouTubeSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let ytDlp = PathUtils.ytDlpPath
        guard FileManager.default.isExecutableFile(atPath: ytDlp.path) else {
            throw YouTubeSearchError.binaryMissing
        }

        let template = ["%(id)s", "%(title)s", "%(channel)s", "%(duration)s", "%(thumbnail)s"]
            .joined(separator: Self.sep)

        let (stdout, stderr, code) = try await ProcessRunner().run(
            executable: ytDlp,
            arguments: [
                "ytsearch\(limit):\(q)",
                "--flat-playlist",
                "--no-warnings",
                "--ignore-errors",
                "--print", template,
            ],
            timeout: 30
        )

        guard code == 0 || !stdout.isEmpty else {
            throw YouTubeSearchError.failed(stderr.isEmpty ? "Search failed." : stderr)
        }

        return stdout
            .split(separator: "\n")
            .compactMap { parse(String($0)) }
    }

    private func parse(_ line: String) -> YouTubeSearchResult? {
        let parts = line.components(separatedBy: Self.sep)
        guard parts.count >= 5 else { return nil }
        let id = parts[0].trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id.uppercased() != "NA" else { return nil }

        func clean(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespaces)
            return (t.isEmpty || t.uppercased() == "NA") ? "" : t
        }

        return YouTubeSearchResult(
            id: id,
            title: clean(parts[1]).isEmpty ? "Untitled" : clean(parts[1]),
            channel: clean(parts[2]),
            duration: Double(clean(parts[3])),
            thumbnailURL: URL(string: clean(parts[4]))
        )
    }
}
