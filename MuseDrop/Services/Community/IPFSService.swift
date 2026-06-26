//
//  IPFSService.swift
//  MuseDrop
//
//  Phase 3 of the community wall: true peer-to-peer content. Where Nostr carries
//  the decentralized *index* (who shared what), IPFS carries the *bytes* (the
//  actual `.kekapack`). We run **kubo** (the Go IPFS node) as a sidecar daemon —
//  the same way the app already bundles + shells out to yt-dlp/ffmpeg — and talk
//  to its local HTTP RPC API. The binary is fetched on first community use (not
//  checked into the repo) and lives alongside the other tools in the bin dir.
//
//  Everything here is additive and best-effort: if kubo is unavailable (offline,
//  download failed), publishing still works locally (no CID) exactly as before.
//

import Foundation
import AppKit

actor IPFSService {
    static let shared = IPFSService()

    /// Pinned kubo release. Bump when validated against a newer node.
    private static let kuboVersion = "v0.42.0"

    /// Custom localhost ports so we never clash with a user's own `~/.ipfs` node.
    private static let apiPort = 5101
    private static let gatewayPort = 8181
    private static let swarmPort = 4101
    private static var apiBase: String { "http://127.0.0.1:\(apiPort)/api/v0" }

    private static let startupTimeout: TimeInterval = 45
    private static let fetchTimeout: TimeInterval = 90

    private var daemonReady = false
    private var daemonRunner: ProcessRunner?
    private var daemonTask: Task<Void, Never>?

    private let fileManager = FileManager.default
    private let log = LogService.shared

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            // Best-effort: terminate the child daemon so it doesn't outlive the app.
            Task { await IPFSService.shared.shutdown() }
        }
    }

    // MARK: - Public API

    /// Warm up the daemon ahead of time (e.g. when the Community tab opens) so the
    /// first publish/import doesn't pay the download+startup cost inline. Fire-and-forget.
    func prewarm() {
        Task { try? await ensureDaemon() }
    }

    /// Add a file to IPFS and return its CID (pinned locally so we keep seeding it).
    func add(_ fileURL: URL) async throws -> String {
        try await ensureDaemon()

        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: "\(Self.apiBase)/add?pin=true&cid-version=1") else {
            throw IPFSError.addFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let cid = Self.parseAddResponse(data) else {
            throw IPFSError.addFailed
        }
        log.info("IPFS add → \(cid)")
        return cid
    }

    /// Fetch a CID's bytes from the network and write them to a temp `.kekapack`.
    func fetch(cid: String) async throws -> URL {
        try await ensureDaemon()

        guard let encoded = cid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.apiBase)/cat?arg=\(encoded)") else {
            throw IPFSError.fetchFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.fetchTimeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw IPFSError.fetchFailed }

        let dest = try FileUtils.createTempFile(extension: "kekapack")
        try data.write(to: dest)
        return dest
    }

    /// Terminate the daemon (best-effort; a fresh launch will reuse a live one).
    func shutdown() {
        daemonTask?.cancel()
        daemonRunner?.cancel()
        daemonRunner = nil
        daemonReady = false
    }

    // MARK: - Daemon lifecycle

    private func ensureDaemon() async throws {
        if daemonReady { return }

        // A daemon from a previous launch (ours or the user's) may already serve
        // our port — reuse it rather than fighting over the repo lock.
        if await apiResponds() { daemonReady = true; return }

        let binary = try await binaryURL()
        let repo = PathUtils.ipfsRepoDirectory
        try fileManager.createDirectory(at: repo, withIntermediateDirectories: true)
        let env = ["IPFS_PATH": repo.path]

        if !fileManager.fileExists(atPath: repo.appendingPathComponent("config").path) {
            _ = try await ProcessRunner().run(executable: binary, arguments: ["init"], timeout: 60, environment: env)
            // Bind to custom localhost ports to avoid colliding with a user's node.
            let configs: [[String]] = [
                ["config", "Addresses.API", "/ip4/127.0.0.1/tcp/\(Self.apiPort)"],
                ["config", "Addresses.Gateway", "/ip4/127.0.0.1/tcp/\(Self.gatewayPort)"],
                ["config", "--json", "Addresses.Swarm",
                 "[\"/ip4/0.0.0.0/tcp/\(Self.swarmPort)\",\"/ip6/::/tcp/\(Self.swarmPort)\"]"]
            ]
            for cfg in configs {
                _ = try? await ProcessRunner().run(executable: binary, arguments: cfg, timeout: 30, environment: env)
            }
        }

        // Launch the long-running daemon and drain its output in a detached task.
        let runner = ProcessRunner()
        daemonRunner = runner
        let stream = runner.runWithProgress(
            executable: binary,
            arguments: ["daemon", "--migrate=true"],
            environment: env
        )
        daemonTask = Task.detached {
            do { for try await _ in stream {} } catch { /* daemon exited / cancelled */ }
        }

        try await waitForAPI(timeout: Self.startupTimeout)
        daemonReady = true
        log.info("IPFS daemon ready on 127.0.0.1:\(Self.apiPort)")
    }

    /// Resolve the kubo binary, downloading it on first use.
    private func binaryURL() async throws -> URL {
        if let existing = PathUtils.getIPFSBinaryPath() { return existing }
        try await downloadBinary()
        guard let url = PathUtils.getIPFSBinaryPath() else { throw IPFSError.binaryUnavailable }
        return url
    }

    private func downloadBinary() async throws {
        try PathUtils.ensureDirectoriesExist()

        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "amd64"
            #endif
        }()
        let version = Self.kuboVersion
        let urlString = "https://dist.ipfs.tech/kubo/\(version)/kubo_\(version)_darwin-\(arch).tar.gz"
        guard let url = URL(string: urlString) else { throw IPFSError.binaryUnavailable }

        log.info("Downloading kubo \(version) (\(arch))…")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw IPFSError.binaryUnavailable }

        let work = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }

        let tarball = work.appendingPathComponent("kubo.tar.gz")
        try data.write(to: tarball)

        // The tarball expands to `kubo/ipfs` (+ install.sh). Extract with system tar.
        _ = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", tarball.path, "-C", work.path],
            timeout: 120
        )

        let extracted = work.appendingPathComponent("kubo/ipfs")
        guard fileManager.fileExists(atPath: extracted.path) else { throw IPFSError.binaryUnavailable }

        let dest = PathUtils.ipfsBinaryPath
        try? fileManager.removeItem(at: dest)
        try fileManager.moveItem(at: extracted, to: dest)
        FileUtils.ensureBinaryReady(dest) // chmod 755 + strip quarantine
        log.info("kubo installed at \(dest.path)")
    }

    // MARK: - Health

    private func waitForAPI(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await apiResponds() { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        throw IPFSError.daemonStartTimeout
    }

    private func apiResponds() async -> Bool {
        guard let url = URL(string: "\(Self.apiBase)/id") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// `/add` streams one JSON object per line; the last with a `Hash` is the root.
    private static func parseAddResponse(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let hash = obj["Hash"] as? String, !hash.isEmpty {
                return hash
            }
        }
        return nil
    }
}

enum IPFSError: LocalizedError {
    case binaryUnavailable
    case daemonStartTimeout
    case addFailed
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .binaryUnavailable:  return "Couldn't install the IPFS component needed to share content."
        case .daemonStartTimeout: return "The IPFS node didn't start in time."
        case .addFailed:          return "Couldn't add this pack to IPFS."
        case .fetchFailed:        return "Couldn't fetch this pack from the network."
        }
    }
}
