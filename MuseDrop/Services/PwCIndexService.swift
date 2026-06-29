//
//  PwCIndexService.swift
//  Kekasatori
//
//  Local lookups into the Papers with Code snapshot (code links, indexed by
//  arXiv id). The SQLite index is downloaded once from our CC-BY-SA mirror
//  release into Application Support, then every query is local + offline.
//
//  Data: Papers with Code (Meta AI), CC-BY-SA 4.0. Mirror:
//  github.com/harikanthl/kekasatori-pwc-data
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct PwCCodeLink: Identifiable, Hashable {
    let id = UUID()
    let repoURL: String
    let isOfficial: Bool
    let framework: String

    /// `owner/repo` from a GitHub URL, else the raw URL.
    var displayName: String {
        guard let host = URL(string: repoURL)?.host, host.contains("github") else { return repoURL }
        let parts = (URL(string: repoURL)?.path ?? "").split(separator: "/").prefix(2)
        return parts.isEmpty ? repoURL : parts.joined(separator: "/")
    }

    var frameworkLabel: String? {
        switch framework.lowercased() {
        case "pytorch": return "PyTorch"
        case "tf", "tensorflow": return "TensorFlow"
        case "jax": return "JAX"
        case "mxnet": return "MXNet"
        case "paddlepaddle": return "Paddle"
        case "", "none": return nil
        default: return framework
        }
    }
}

actor PwCIndexService {
    static let shared = PwCIndexService()

    private static let assetURL = URL(string:
        "https://github.com/harikanthl/kekasatori-pwc-data/releases/download/v1/pwc-index.sqlite")!

    private var dbURL: URL {
        PathUtils.applicationSupportDirectory.appendingPathComponent("Database/pwc-index.sqlite")
    }

    private var ensureTask: Task<Bool, Never>?

    /// Whether the index is already downloaded (no network).
    func isDownloaded() -> Bool { FileManager.default.fileExists(atPath: dbURL.path) }

    /// Code repositories for a paper — official-first, deduped by repo, capped.
    /// Downloads the index on first call if absent (returns [] on failure).
    func codeLinks(arxivId raw: String, limit: Int = 8) async -> [PwCCodeLink] {
        let id = PaperHit.normalizedArxivId(raw)
        guard !id.isEmpty, await ensureAvailable() else { return [] }
        return Self.query(dbPath: dbURL.path, arxivId: id, limit: limit)
    }

    // MARK: - Download (once, shared across concurrent callers)

    private func ensureAvailable() async -> Bool {
        if FileManager.default.fileExists(atPath: dbURL.path) { return true }
        if let task = ensureTask { return await task.value }
        let dest = dbURL
        let task = Task { await Self.download(from: Self.assetURL, to: dest) }
        ensureTask = task
        let ok = await task.value
        ensureTask = nil
        return ok
    }

    private static func download(from url: URL, to dest: URL) async -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Query (read-only)

    private static func query(dbPath: String, arxivId: String, limit: Int) -> [PwCCodeLink] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT is_official, COALESCE(framework,''), repo_url " +
                  "FROM paper_code WHERE arxiv_id = ? ORDER BY is_official DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, arxivId, -1, SQLITE_TRANSIENT)

        var seen = Set<String>()
        var out: [PwCCodeLink] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let isOfficial = sqlite3_column_int(stmt, 0) != 0
            let framework = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard let repoC = sqlite3_column_text(stmt, 2) else { continue }
            let repo = String(cString: repoC)
            guard !repo.isEmpty, seen.insert(repo).inserted else { continue }
            out.append(PwCCodeLink(repoURL: repo, isOfficial: isOfficial, framework: framework))
            if out.count >= limit { break }
        }
        return out
    }
}
