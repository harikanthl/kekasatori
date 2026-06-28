//
//  MuseDropApp.swift
//  MuseDrop
//
//  Created by harikanth lingutla on 11/20/25.
//

import SwiftUI
import SwiftData

@main
struct MuseDropApp: App {
    private let dataStore = DataStore.shared
    @StateObject private var updater = AppUpdater()

    init() {
        setupApp()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(dataStore.modelContainer)
        .commands {
            CheckForUpdatesCommand(updater: updater)
        }
    }
    
    private func setupApp() {
        // Disk-backed shared image/URL cache so AsyncImage (paper thumbnails,
        // library art, search results) reuses downloads across the app.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,    // 64 MB
            diskCapacity: 512 * 1024 * 1024      // 512 MB
        )

        // Create directories
        do {
            try PathUtils.ensureDirectoriesExist()
        } catch {
            LogService.shared.error("Failed to create directories", error: error)
        }
        
        // Setup binaries on first run
        setupBinaries()
        
        // Start automatic binary updates
        BinaryUpdateService.shared.startAutoUpdate()
        
        // Load library
        _ = LibraryManager.shared
    }
    
    private func setupBinaries() {
        let binDir = PathUtils.binDirectory
        let ytDlpPath = PathUtils.ytDlpPath
        let ffmpegPath = PathUtils.ffmpegPath
        
        // Check if binaries already exist
        if FileManager.default.fileExists(atPath: ytDlpPath.path) &&
           FileManager.default.fileExists(atPath: ffmpegPath.path) {
            // Verify they're executable and remove quarantine if needed
            ensureExecutable(ytDlpPath)
            ensureExecutable(ffmpegPath)
            return
        }
        
        // Try to copy from bundle Resources (Xcode 16+ uses flat structure)
        var bundleYtDlp: URL?
        var bundleFfmpeg: URL?

        // Try yt-dlp first without subdirectory (Xcode 16+ flat structure)
        if let ytDlp = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) {
            bundleYtDlp = ytDlp
        } else if let ytDlp = Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "bin") {
            // Fallback to bin subdirectory
            bundleYtDlp = ytDlp
        } else if let ytDlpMacos = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) {
            bundleYtDlp = ytDlpMacos
        } else if let ytDlpMacos = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil, subdirectory: "bin") {
            bundleYtDlp = ytDlpMacos
        }

        // Try to find ffmpeg binary
        if let ffmpeg = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            bundleFfmpeg = ffmpeg
        } else {
            bundleFfmpeg = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin")
        }
        
        if let bundleYtDlp = bundleYtDlp, let bundleFfmpeg = bundleFfmpeg {
            do {
                try FileUtils.createDirectory(at: binDir)
                
                // Copy yt-dlp
                try FileUtils.copyFile(from: bundleYtDlp, to: ytDlpPath)
                ensureExecutable(ytDlpPath)
                
                // Copy ffmpeg
                try FileUtils.copyFile(from: bundleFfmpeg, to: ffmpegPath)
                ensureExecutable(ffmpegPath)
                
                LogService.shared.info("Binaries copied and made executable")
            } catch {
                LogService.shared.error("Failed to copy binaries from bundle", error: error)
            }
        } else {
            var missing: [String] = []
            if bundleYtDlp == nil {
                missing.append("yt-dlp (or yt-dlp_macos)")
            }
            if bundleFfmpeg == nil {
                missing.append("ffmpeg")
            }
            LogService.shared.warning("Binaries not found in bundle: \(missing.joined(separator: ", ")). Please add them to Resources/bin")
        }
    }
    
    private func ensureExecutable(_ url: URL) {
        FileUtils.ensureBinaryReady(url)
    }
}
