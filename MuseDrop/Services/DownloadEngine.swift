//
//  DownloadEngine.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation
import Combine

@MainActor
class DownloadEngine: ObservableObject {
    static let shared = DownloadEngine()
    
    /// One runner per active download so cancel/progress never cross wires.
    private var downloadRunners: [UUID: ProcessRunner] = [:]
    private let libraryManager = LibraryManager.shared
    private let logService = LogService.shared
    
    @Published var activeDownloads: [UUID: DownloadItem] = [:]
    
    private init() {}
    
    private func runner(for downloadId: UUID) -> ProcessRunner {
        if let existing = downloadRunners[downloadId] {
            return existing
        }
        let runner = ProcessRunner()
        downloadRunners[downloadId] = runner
        return runner
    }
    
    private func releaseRunner(for downloadId: UUID) {
        downloadRunners.removeValue(forKey: downloadId)
    }
    
    func download(url: String, type: DownloadType, destination: URL? = nil) async throws -> DownloadItem {
        let item = DownloadItem(url: url, status: .queued)
        libraryManager.addDownload(item)
        activeDownloads[item.id] = item
        
        // Run download in background, but update UI on main thread
        Task { @MainActor in
            await performDownload(item: item, type: type, destination: destination)
        }
        
        return item
    }
    
    nonisolated private func performDownload(item: DownloadItem, type: DownloadType, destination: URL?) async {
        var currentItem = item
        currentItem.status = .downloading
        let itemToUpdate = currentItem
        await MainActor.run {
            self.updateItem(itemToUpdate)
        }
        
        let processRunner = await MainActor.run { self.runner(for: item.id) }
        defer {
            Task { @MainActor in
                self.releaseRunner(for: item.id)
            }
        }
        
        let outputDir = destination ?? (type == .audio ? PathUtils.audioDirectory : PathUtils.videoDirectory)
        
        // Keep yt-dlp current before downloading (YouTube breaks older extractors frequently).
        await BinaryUpdateService.shared.ensureUpToDate()
        
        guard let ytDlpPath = PathUtils.getYtDlpPath() else {
            let errorMsg = "yt-dlp not found. Restart the app to download it automatically."
            logService.error(errorMsg)
            currentItem.status = .failed
            currentItem.errorMessage = errorMsg
            let failedItem = currentItem
            await MainActor.run { self.updateItem(failedItem) }
            return
        }

        logService.info("Using yt-dlp at: \(ytDlpPath.path)")

        guard let ffmpegPath = PathUtils.getFfmpegPath() else {
            let errorMsg = "ffmpeg not found. Restart the app to restore bundled binaries."
            logService.error(errorMsg)
            currentItem.status = .failed
            currentItem.errorMessage = errorMsg
            let failedItem = currentItem
            await MainActor.run { self.updateItem(failedItem) }
            return
        }

        logService.info("Using ffmpeg at: \(ffmpegPath.path)")
        
        do {
            // Build yt-dlp arguments based on 2025 best practices
            // Ensure output directory exists
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            
            var arguments: [String] = [
                "--no-playlist",                    // Download only single video, not playlist
                "--write-info-json",                // Save metadata
                "--write-thumbnail",                 // Save thumbnail
                "--ffmpeg-location", ffmpegPath.path,  // Explicitly tell yt-dlp where ffmpeg is
                "--output", outputDir.appendingPathComponent("%(title)s.%(ext)s").path,
                "--no-warnings",                    // Reduce noise in output
                "--progress",                       // Show progress
                "--newline"                         // Use newlines for better parsing
            ]
            
            if type == .audio {
                // For audio: use best audio format and extract to mp3
                // According to yt-dlp docs: -f 'ba[acodec^=mp3]/ba/b' -x --audio-format mp3
                arguments.append(contentsOf: [
                    "--format", "bestaudio/best",   // Prefer best audio-only, fallback to best combined
                    "--extract-audio",               // Extract audio from video if needed
                    "--audio-format", "mp3",         // Convert to mp3
                    "--audio-quality", "0"          // Best quality (0 = best, 10 = worst)
                ])
            } else {
                // For video: use recommended format selector from yt-dlp docs
                // Default is bv*+ba/b (best video* + best audio / best)
                // We add mp4 preference and merge output format
                arguments.append(contentsOf: [
                    "--format", "bv*+ba/b",         // Best video (may contain audio) + best audio / best
                    "--merge-output-format", "mp4"  // Ensure final output is mp4 container
                ])
            }
            
            arguments.append(item.url)
            
            // Run yt-dlp
            let stream = processRunner.runWithProgress(
                executable: ytDlpPath,
                arguments: arguments,
                workingDirectory: outputDir
            )
            
            for try await line in stream {
                if Task.isCancelled { break }
                parseProgress(line: line, item: &currentItem)
                let itemToUpdate = currentItem
                await MainActor.run { self.updateItem(itemToUpdate) }
            }
            
            // Get metadata from info json
            if let info = try? await extractMetadata(from: outputDir, url: item.url) {
                currentItem.title = info.title
                currentItem.thumbnail = info.thumbnail
                currentItem.format = info.format
            }
            
            // Find output file
            if let outputFile = findOutputFile(in: outputDir, url: item.url) {
                currentItem.outputPath = outputFile
                currentItem.progress = 1.0
                currentItem.status = .completed
            } else {
                currentItem.status = .failed
                currentItem.errorMessage = "Download completed but output file not found. Check logs for details."
                logService.error("Output file not found for download: \(item.url)")
            }
            
            let finalItem = currentItem
            await MainActor.run {
                self.updateItem(finalItem)
                self.activeDownloads.removeValue(forKey: item.id)
            }
            
        } catch {
            let errorMessage: String
            if error is CancellationError {
                errorMessage = "Download cancelled."
            } else if let processError = error as? ProcessError {
                switch processError {
                case .nonZeroExit(let code, let stderr):
                    errorMessage = stderr.isEmpty ? "Process exited with code \(code)" : stderr
                case .executableNotFound:
                    errorMessage = "Executable not found"
                case .executionFailed(let underlyingError):
                    errorMessage = "Execution failed: \(underlyingError.localizedDescription)"
                case .timedOut(let seconds):
                    errorMessage = "Process timed out after \(Int(seconds)) seconds"
                }
            } else {
                errorMessage = error.localizedDescription
            }
            
            logService.error("Download failed: \(errorMessage)", error: error)
            currentItem.status = .failed
            currentItem.errorMessage = errorMessage
            let failedItem = currentItem
            await MainActor.run {
                self.updateItem(failedItem)
                self.activeDownloads.removeValue(forKey: item.id)
            }
        }
    }
    
    nonisolated private func parseProgress(line: String, item: inout DownloadItem) {
        // Parse yt-dlp progress output
        // Example: [download]  45.2% of 123.45MiB at 2.34MiB/s ETA 00:30
        if line.contains("[download]") {
            let pattern = #"(\d+\.?\d*)%"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let range = Range(match.range(at: 1), in: line),
                   let progress = Double(line[range]) {
                    item.progress = progress / 100.0
                }
            }
        }
    }
    
    nonisolated private func extractMetadata(from directory: URL, url: String) async throws -> (title: String, thumbnail: URL?, format: String) {
        // Find info json file
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let infoFile = files.first(where: { $0.lastPathComponent.hasSuffix(".info.json") }) else {
            return ("", nil, "")
        }
        
        let data = try Data(contentsOf: infoFile)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        let title = json?["title"] as? String ?? ""
        let format = json?["format"] as? String ?? ""
        
        var thumbnail: URL?
        if let thumbFile = files.first(where: { $0.pathExtension == "jpg" || $0.pathExtension == "webp" }) {
            thumbnail = thumbFile
        }
        
        return (title, thumbnail, format)
    }
    
    nonisolated private func findOutputFile(in directory: URL, url: String) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return nil
        }
        
        // Find the most recently modified media file
        let mediaFiles = files.filter { file in
            let ext = file.pathExtension.lowercased()
            return ["mp3", "mp4", "m4a", "webm", "mkv", "mov"].contains(ext)
        }
        
        // Sort by modification date and return the most recent
        let filesWithDates = mediaFiles.compactMap { file -> (URL, Date)? in
            guard let resourceValues = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = resourceValues.contentModificationDate else {
                return nil
            }
            return (file, date)
        }
        
        return filesWithDates.max(by: { $0.1 < $1.1 })?.0
    }
    
    private func updateItem(_ item: DownloadItem) {
        // @MainActor ensures we're always on main thread
        activeDownloads[item.id] = item
        libraryManager.updateDownload(item)
    }
    
    func cancelDownload(_ item: DownloadItem) {
        downloadRunners[item.id]?.cancel()
        releaseRunner(for: item.id)
        var updatedItem = item
        updatedItem.status = .failed
        updatedItem.errorMessage = "Download cancelled."
        updateItem(updatedItem)
        activeDownloads.removeValue(forKey: item.id)
    }

    func getDownloadItem(itemId: UUID) -> DownloadItem? {
        // Check active downloads first
        if let item = activeDownloads[itemId] {
            return item
        }
        // If not active, check library manager
        return libraryManager.getDownload(by: itemId)
    }
}

enum DownloadType {
    case audio
    case video
}

