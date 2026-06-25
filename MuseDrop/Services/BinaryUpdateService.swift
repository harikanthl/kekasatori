//
//  BinaryUpdateService.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

actor BinaryUpdateService {
    static let shared = BinaryUpdateService()

    private let logService = LogService.shared

    // Check every 6 hours (21600 seconds)
    private nonisolated let updateInterval: TimeInterval = 6 * 60 * 60

    // GitHub API endpoint for yt-dlp releases
    private nonisolated let githubAPIURL = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"

    // macOS standalone binary (recommended for MuseDrop on macOS)
    private nonisolated let latestDownloadURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

    private var updateTask: Task<Void, Never>?
    private var autoUpdateLoop: Task<Void, Never>?

    private init() {}

    /// Start the automatic update checker. Safe to call synchronously from app
    /// bootstrap; the periodic loop runs on the actor (not a RunLoop timer).
    nonisolated func startAutoUpdate() {
        Task { await self.beginAutoUpdateLoop() }
    }

    private func beginAutoUpdateLoop() {
        autoUpdateLoop?.cancel()
        autoUpdateLoop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.updateInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.ensureUpToDate()
            }
        }
        logService.info("Binary update service started. Checking every 6 hours.")
    }

    /// Check for updates once, deduplicating concurrent callers (e.g. app launch + download).
    func ensureUpToDate() async {
        if let updateTask {
            await updateTask.value
            return
        }

        let task = Task {
            await checkAndUpdate()
        }
        updateTask = task
        await task.value
        updateTask = nil
    }

    /// Stop the automatic update checker
    nonisolated func stopAutoUpdate() {
        Task { await self.cancelAutoUpdateLoop() }
    }

    private func cancelAutoUpdateLoop() {
        autoUpdateLoop?.cancel()
        autoUpdateLoop = nil
    }
    
    /// Check for updates and update if available
    func checkAndUpdate() async {
        logService.info("Checking for yt-dlp updates...")
        
        do {
            let latestVersion = try await getLatestVersion()
            let currentVersion = await getCurrentVersion()
            
            logService.info("Current version: \(currentVersion ?? "unknown"), Latest version: \(latestVersion)")
            
            if let current = currentVersion, current == latestVersion {
                logService.info("yt-dlp is already up to date")
                return
            }
            
            logService.info("Update available. Downloading yt-dlp \(latestVersion)...")
            try await downloadAndUpdate(to: latestVersion)
            logService.info("yt-dlp successfully updated to version \(latestVersion)")
            
        } catch {
            logService.error("Failed to check/update yt-dlp", error: error)
        }
    }
    
    /// Get the latest version from GitHub API
    private func getLatestVersion() async throws -> String {
        guard let url = URL(string: githubAPIURL) else {
            throw UpdateError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.networkError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw UpdateError.invalidResponse
        }
        
        // Remove 'v' prefix if present (e.g., "v2025.11.12" -> "2025.11.12")
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
    
    /// Get the current installed version
    private func getCurrentVersion() async -> String? {
        guard let ytDlpPath = PathUtils.getYtDlpPath() else {
            return nil
        }

        // ProcessRunner reads stdout/stderr via readability handlers, avoiding the
        // pipe-buffer deadlock of waitUntilExit()-before-read, and never blocks a
        // cooperative thread.
        do {
            let result = try await ProcessRunner().run(
                executable: ytDlpPath,
                arguments: ["--version"],
                timeout: 30
            )
            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        } catch {
            logService.error("Failed to get current version", error: error)
            return nil
        }
    }
    
    /// Download and update yt-dlp to the specified version
    private func downloadAndUpdate(to version: String) async throws {
        guard let downloadURL = URL(string: latestDownloadURL) else {
            throw UpdateError.invalidURL
        }
        
        try PathUtils.ensureDirectoriesExist()
        
        let ytDlpPath = PathUtils.ytDlpPath
        let tempPath = ytDlpPath.appendingPathExtension("tmp")
        
        // Download the new binary
        logService.info("Downloading yt-dlp from: \(latestDownloadURL)")
        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed
        }
        
        // Write to temporary file
        try data.write(to: tempPath)
        
        // Verify it's a valid binary
        guard FileManager.default.fileExists(atPath: tempPath.path) else {
            throw UpdateError.downloadFailed
        }
        
        // Ensure binary is ready (executable + no quarantine)
        FileUtils.ensureBinaryReady(tempPath)
        
        // Verify the new binary works (ProcessRunner throws on non-zero exit)
        do {
            _ = try await ProcessRunner().run(
                executable: tempPath,
                arguments: ["--version"],
                timeout: 30
            )
        } catch {
            try? FileManager.default.removeItem(at: tempPath)
            throw UpdateError.invalidBinary
        }

        // Atomically replace the live binary with the verified download. Using
        // replaceItemAt avoids the previous remove-then-move sequence that could
        // leave yt-dlp missing if interrupted or run concurrently.
        if FileManager.default.fileExists(atPath: ytDlpPath.path) {
            _ = try FileManager.default.replaceItemAt(ytDlpPath, withItemAt: tempPath)
        } else {
            try FileManager.default.moveItem(at: tempPath, to: ytDlpPath)
        }
        try? FileManager.default.removeItem(at: tempPath)

        logService.info("yt-dlp updated successfully to version \(version)")
    }
    
    /// Manual update check (can be called from UI)
    func manualUpdateCheck() async {
        await ensureUpToDate()
    }
}

enum UpdateError: LocalizedError {
    case invalidURL
    case networkError
    case invalidResponse
    case downloadFailed
    case permissionError
    case invalidBinary
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for update check"
        case .networkError:
            return "Network error while checking for updates"
        case .invalidResponse:
            return "Invalid response from GitHub API"
        case .downloadFailed:
            return "Failed to download new binary"
        case .permissionError:
            return "Failed to set executable permissions"
        case .invalidBinary:
            return "Downloaded binary is invalid or corrupted"
        }
    }
}

