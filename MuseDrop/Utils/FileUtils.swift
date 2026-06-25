//
//  FileUtils.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation
import AppKit

struct FileUtils {
    static func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    static func cleanFilename(_ filename: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/:?<>|\\")
        var cleaned = filename.components(separatedBy: invalidChars).joined(separator: "_")
        
        // Remove leading/trailing spaces and dots
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        
        // Limit length
        if cleaned.count > 255 {
            cleaned = String(cleaned.prefix(255))
        }
        
        return cleaned.isEmpty ? "untitled" : cleaned
    }
    
    static func moveFile(from source: URL, to destination: URL) throws {
        let destinationDir = destination.deletingLastPathComponent()
        try createDirectory(at: destinationDir)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        
        try FileManager.default.moveItem(at: source, to: destination)
    }
    
    static func copyFile(from source: URL, to destination: URL) throws {
        let destinationDir = destination.deletingLastPathComponent()
        try createDirectory(at: destinationDir)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        
        try FileManager.default.copyItem(at: source, to: destination)
    }
    
    static func deleteFile(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    
    static func revealInFinder(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    static func openFile(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
    
    static func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }
    
    static func createTempFile(extension ext: String = "tmp") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString + "." + ext
        return tempDir.appendingPathComponent(filename)
    }
    
    /// Ensure a binary is executable and has no quarantine attribute
    /// For sandboxed apps, we try multiple methods to set permissions
    static func ensureBinaryReady(_ url: URL) {
        // Method 1: Use FileManager.setAttributes with posixPermissions (most reliable in sandbox)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            LogService.shared.warning("Failed to set posixPermissions via FileManager: \(error.localizedDescription)")
        }
        
        // Method 2: Try using NSURL setResourceValue
        try? (url as NSURL).setResourceValue(true, forKey: .isExecutableKey)

        // Method 3: Remove the quarantine attribute if present (matters for
        // binaries fetched at runtime by BinaryUpdateService). Direct syscall
        // instead of spawning /usr/bin/xattr — no subprocess, so it never blocks
        // the calling (sometimes main) thread. The executable bit is already
        // handled by FileManager posixPermissions above, so the old /bin/chmod
        // subprocess is no longer needed.
        _ = url.path.withCString { removexattr($0, "com.apple.quarantine", 0) }
        
        // Verify permissions were set (for logging)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let permissions = attributes[.posixPermissions] as? NSNumber {
            LogService.shared.debug("Binary permissions set to: \(String(format: "%o", permissions.intValue))")
        }
    }
}

