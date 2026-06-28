//
//  PathUtils.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

struct PathUtils {
    static let appName = "Kekasatori"
    
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName)
    }
    
    static var libraryDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Library")
    }
    
    static var audioDirectory: URL {
        libraryDirectory.appendingPathComponent("Audio")
    }
    
    static var videoDirectory: URL {
        libraryDirectory.appendingPathComponent("Video")
    }
    
    static var coversDirectory: URL {
        libraryDirectory.appendingPathComponent("Covers")
    }
    
    static var summariesDirectory: URL {
        libraryDirectory.appendingPathComponent("Summaries")
    }
    
    static var analysisDirectory: URL {
        libraryDirectory.appendingPathComponent("Analysis")
    }
    
    static var databaseDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Database")
    }
    
    static var swiftDataStoreURL: URL {
        databaseDirectory.appendingPathComponent("Kekasatori.store")
    }
    
    static var downloadsJSONPath: URL {
        databaseDirectory.appendingPathComponent("downloads.json")
    }
    
    static var binDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("bin")
    }
    
    static var canvasDirectory: URL {
        libraryDirectory.appendingPathComponent("Canvas")
    }
    
    static var notebookDirectory: URL {
        libraryDirectory.appendingPathComponent("Notebook")
    }
    
    static var papersDirectory: URL {
        libraryDirectory.appendingPathComponent("Papers")
    }

    /// Community sharing scratch space (local discovery-wall stub).
    static var communityDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Community")
    }

    /// Local index of community posts (stub backend; replaced by Nostr later).
    static var communityIndexFile: URL {
        communityDirectory.appendingPathComponent("index.json")
    }

    /// Published `.kekapack` files seeded by this user (also added to IPFS).
    static var communityPacksDirectory: URL {
        communityDirectory.appendingPathComponent("packs")
    }

    /// This user's own published Nostr events (JSON), re-broadcast each session
    /// so posts survive eviction from free relays.
    static var communityMyPostsDirectory: URL {
        communityDirectory.appendingPathComponent("my-posts")
    }

    /// The bundled/downloaded kubo (IPFS) binary used for Phase-3 content P2P.
    static var ipfsBinaryPath: URL {
        binDirectory.appendingPathComponent("ipfs")
    }

    /// kubo repo, kept isolated from any system-wide `~/.ipfs` the user runs.
    static var ipfsRepoDirectory: URL {
        communityDirectory.appendingPathComponent("ipfs-repo")
    }

    /// Locate the kubo binary: app-support copy first, then the app bundle.
    static func getIPFSBinaryPath() -> URL? {
        if FileManager.default.fileExists(atPath: ipfsBinaryPath.path) {
            return ipfsBinaryPath
        }
        if let bundled = Bundle.main.url(forResource: "ipfs", withExtension: nil),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        if let bundled = Bundle.main.url(forResource: "ipfs", withExtension: nil, subdirectory: "bin"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return nil
    }

    static func paperBundleDirectory(itemId: UUID) -> URL {
        papersDirectory.appendingPathComponent(itemId.uuidString, isDirectory: true)
    }
    
    static func notebookDayDirectory(downloadId: UUID, dayKey: String) -> URL {
        notebookDirectory
            .appendingPathComponent(downloadId.uuidString, isDirectory: true)
            .appendingPathComponent(dayKey, isDirectory: true)
    }
    
    static func manimJobDirectory(downloadId: UUID, dayKey: String, jobId: UUID) -> URL {
        notebookDayDirectory(downloadId: downloadId, dayKey: dayKey)
            .appendingPathComponent("jobs", isDirectory: true)
            .appendingPathComponent(jobId.uuidString, isDirectory: true)
    }
    
    /// TeX Live binary directories (BasicTeX / MacTeX). GUI apps often lack these on PATH.
    static func latexBinDirectories() -> [String] {
        var paths = ["/Library/TeX/texbin"]
        
        let texliveRoot = "/usr/local/texlive"
        if let distributions = try? FileManager.default.contentsOfDirectory(atPath: texliveRoot) {
            for name in distributions.sorted().reversed() {
                let universal = "\(texliveRoot)/\(name)/bin/universal-darwin"
                if FileManager.default.fileExists(atPath: universal) {
                    paths.append(universal)
                }
                let arm64 = "\(texliveRoot)/\(name)/bin/arm64-darwin"
                if FileManager.default.fileExists(atPath: arm64) {
                    paths.append(arm64)
                }
                let x86 = "\(texliveRoot)/\(name)/bin/x86_64-darwin"
                if FileManager.default.fileExists(atPath: x86) {
                    paths.append(x86)
                }
            }
        }
        
        return paths
    }
    
    static func resolveLatexExecutable() -> URL? {
        let names = ["latex", "pdflatex", "xelatex"]
        for directory in latexBinDirectories() {
            for name in names {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }
    
    /// Locate bundled musedrop_scene.py (Xcode may flatten Resources or preserve manim/ subdirectory).
    static func getManimSceneTemplateURL() -> URL? {
        // Flat in Resources (Xcode 16+ synchronized root group)
        if let url = Bundle.main.url(forResource: "musedrop_scene", withExtension: "py") {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // manim/ subdirectory
        if let url = Bundle.main.url(forResource: "musedrop_scene", withExtension: "py", subdirectory: "manim") {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        // Direct resource path fallbacks (mirrors yt-dlp / ffmpeg lookup)
        if let resourcePath = Bundle.main.resourcePath {
            let candidates = [
                "musedrop_scene.py",
                "manim/musedrop_scene.py",
                "Resources/manim/musedrop_scene.py"
            ]
            for relative in candidates {
                let full = URL(fileURLWithPath: resourcePath).appendingPathComponent(relative)
                if FileManager.default.fileExists(atPath: full.path) {
                    return full
                }
            }
        }
        
        // Application Support copy (populated by build script or prior render)
        let appSupportCopy = applicationSupportDirectory
            .appendingPathComponent("manim")
            .appendingPathComponent("musedrop_scene.py")
        if FileManager.default.fileExists(atPath: appSupportCopy.path) {
            return appSupportCopy
        }
        
        return nil
    }
    
    static func canvasBoardDirectory(_ boardId: UUID) -> URL {
        canvasDirectory.appendingPathComponent(boardId.uuidString, isDirectory: true)
    }
    
    static func canvasSceneFile(_ boardId: UUID) -> URL {
        canvasBoardDirectory(boardId).appendingPathComponent("scene.excalidraw.json")
    }
    
    static func canvasFilesDirectory(_ boardId: UUID) -> URL {
        canvasBoardDirectory(boardId).appendingPathComponent("files", isDirectory: true)
    }
    
    static func canvasThumbnailFile(_ boardId: UUID) -> URL {
        canvasBoardDirectory(boardId).appendingPathComponent("thumbnail.png")
    }
    
    static func excalidrawHostIndexURL() -> URL? {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ExcalidrawHost") {
            return url
        }
        if let resourcePath = Bundle.main.resourcePath {
            let nested = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("ExcalidrawHost/index.html")
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
        }
        return nil
    }
    
    /// Directory WKWebView may read when loading the Excalidraw host (index + assets/).
    static func excalidrawHostReadAccessURL() -> URL? {
        guard let indexURL = excalidrawHostIndexURL() else { return nil }
        return indexURL.deletingLastPathComponent()
    }

    /// Bundled Monaco editor host (index.html + vs/). Offline, no CDN.
    static func monacoHostIndexURL() -> URL? {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "MonacoHost") {
            return url
        }
        if let resourcePath = Bundle.main.resourcePath {
            let nested = URL(fileURLWithPath: resourcePath).appendingPathComponent("MonacoHost/index.html")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    /// Directory WKWebView may read when loading Monaco (index + vs/).
    static func monacoHostReadAccessURL() -> URL? {
        monacoHostIndexURL()?.deletingLastPathComponent()
    }
    
    static var ytDlpPath: URL {
        binDirectory.appendingPathComponent("yt-dlp")
    }
    
    static var ffmpegPath: URL {
        binDirectory.appendingPathComponent("ffmpeg")
    }
    
    /// Get yt-dlp path directly from bundle (for sandboxed apps)
    static func getBundleYtDlpPath() -> URL? {
        // Try bundle lookup without subdirectory (Xcode 16+ flat structure)
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try bundle lookup with subdirectory (older structure)
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "bin") {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try direct resource path lookup
        if let resourcePath = Bundle.main.resourcePath {
            let paths = ["yt-dlp", "bin/yt-dlp", "Resources/bin/yt-dlp"]
            for path in paths {
                let fullPath = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: fullPath.path) {
                    return fullPath
                }
            }
        }

        return nil
    }

    /// Get ffmpeg path directly from bundle (for sandboxed apps)
    static func getBundleFfmpegPath() -> URL? {
        // Try bundle lookup without subdirectory (Xcode 16+ flat structure)
        if let bundlePath = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try bundle lookup with subdirectory (older structure)
        if let bundlePath = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin") {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try direct resource path lookup
        if let resourcePath = Bundle.main.resourcePath {
            let paths = ["ffmpeg", "bin/ffmpeg", "Resources/bin/ffmpeg"]
            for path in paths {
                let fullPath = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: fullPath.path) {
                    return fullPath
                }
            }
        }

        return nil
    }

    /// Get yt-dlp path, checking bundle as fallback
    static func getYtDlpPath() -> URL? {
        let appSupportPath = ytDlpPath
        LogService.shared.debug("Checking for yt-dlp at app support: \(appSupportPath.path)")

        if FileManager.default.fileExists(atPath: appSupportPath.path) {
            LogService.shared.debug("Found yt-dlp in app support")
            return appSupportPath
        }

        // Try bundle lookup without subdirectory (Xcode 16+ flat structure)
        LogService.shared.debug("Checking bundle for yt-dlp (no subdirectory)")
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) {
            LogService.shared.debug("Bundle returned path: \(bundlePath.path)")
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                LogService.shared.debug("Found yt-dlp in bundle (flat)")
                return bundlePath
            } else {
                LogService.shared.debug("Bundle path doesn't exist on disk")
            }
        } else {
            LogService.shared.debug("Bundle.main.url returned nil for yt-dlp")
        }

        // Try bundle lookup with subdirectory (older structure)
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "bin") {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try alternative name without subdirectory
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil) {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try alternative name with subdirectory
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil, subdirectory: "bin") {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try direct resource path lookup
        LogService.shared.debug("Checking direct resource paths")

        if let resourcePath = Bundle.main.resourcePath {
            LogService.shared.debug("Bundle resource path: \(resourcePath)")

            let paths = [
                "yt-dlp",              // Flat in Resources (Xcode 16+)
                "bin/yt-dlp",
                "Resources/bin/yt-dlp",
                "yt-dlp_macos",
                "bin/yt-dlp_macos",
                "Resources/bin/yt-dlp_macos"
            ]

            for path in paths {
                let fullPath = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                LogService.shared.debug("Checking path: \(fullPath.path)")
                if FileManager.default.fileExists(atPath: fullPath.path) {
                    LogService.shared.debug("Found yt-dlp at: \(fullPath.path)")
                    return fullPath
                }
            }
        } else {
            LogService.shared.debug("Bundle.main.resourcePath is nil")
        }

        LogService.shared.error("yt-dlp not found anywhere!")
        return nil
    }
    
    /// Get list of all paths checked for yt-dlp (for error messages)
    static func getCheckedYtDlpPaths() -> [String] {
        var paths: [String] = []
        
        // Application Support path
        paths.append("• Application Support: \(ytDlpPath.path)")
        
        // Bundle paths
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp", withExtension: nil, subdirectory: "bin") {
            paths.append("• Bundle (bin subdirectory): \(bundlePath.path)")
        }
        
        if let bundlePath = Bundle.main.url(forResource: "yt-dlp_macos", withExtension: nil, subdirectory: "bin") {
            paths.append("• Bundle (yt-dlp_macos): \(bundlePath.path)")
        }
        
        // Direct resource paths
        if let resourcePath = Bundle.main.resourcePath {
            let directPaths = [
                "bin/yt-dlp",
                "Resources/bin/yt-dlp",
                "yt-dlp",
                "bin/yt-dlp_macos",
                "Resources/bin/yt-dlp_macos"
            ]
            
            for path in directPaths {
                let fullPath = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                paths.append("• Resource path: \(fullPath.path)")
            }
        } else {
            paths.append("• Bundle resource path: (not available)")
        }
        
        return paths
    }
    
    /// Get ffmpeg path, checking bundle as fallback
    static func getFfmpegPath() -> URL? {
        let appSupportPath = ffmpegPath
        if FileManager.default.fileExists(atPath: appSupportPath.path) {
            return appSupportPath
        }

        // Try bundle lookup without subdirectory (Xcode 16+ flat structure)
        if let bundlePath = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try bundle lookup with subdirectory (older structure)
        if let bundlePath = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin") {
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }

        // Try direct resource path lookup
        if let resourcePath = Bundle.main.resourcePath {
            let paths = [
                "ffmpeg",              // Flat in Resources (Xcode 16+)
                "bin/ffmpeg",
                "Resources/bin/ffmpeg"
            ]

            for path in paths {
                let fullPath = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                if FileManager.default.fileExists(atPath: fullPath.path) {
                    return fullPath
                }
            }
        }

        return nil
    }
    
    /// Get list of all paths checked for ffmpeg (for error messages)
    static func getCheckedFfmpegPaths() -> [String] {
        var paths: [String] = []
        
        // Application Support path
        paths.append("• Application Support: \(ffmpegPath.path)")
        
        // Bundle paths
        if let bundlePath = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin") {
            paths.append("• Bundle (bin subdirectory): \(bundlePath.path)")
        }
        
        // Direct resource paths
        if let resourcePath = Bundle.main.resourcePath {
            let directPaths = [
                "bin/ffmpeg",
                "Resources/bin/ffmpeg",
                "ffmpeg"
            ]
            
            for path in directPaths {
                let fullPath = URL(fileURLWithPath: resourcePath).appendingPathComponent(path)
                paths.append("• Resource path: \(fullPath.path)")
            }
        } else {
            paths.append("• Bundle resource path: (not available)")
        }
        
        return paths
    }
    
    static func ensureDirectoriesExist() throws {
        let directories = [
            libraryDirectory,
            audioDirectory,
            videoDirectory,
            coversDirectory,
            summariesDirectory,
            analysisDirectory,
            databaseDirectory,
            binDirectory,
            canvasDirectory,
            notebookDirectory,
            papersDirectory,
            communityDirectory,
            communityPacksDirectory
        ]
        
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}

