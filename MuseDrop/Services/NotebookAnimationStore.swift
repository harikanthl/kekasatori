//
//  NotebookAnimationStore.swift
//  MuseDrop
//

import Foundation

enum NotebookAnimationStore {
    private static let manifestFileName = "animations.json"
    
    static func manifestURL(downloadId: UUID, dayKey: String) -> URL {
        PathUtils.notebookDayDirectory(downloadId: downloadId, dayKey: dayKey)
            .appendingPathComponent(manifestFileName)
    }
    
    static func videoURL(downloadId: UUID, dayKey: String, fileName: String) -> URL {
        PathUtils.notebookDayDirectory(downloadId: downloadId, dayKey: dayKey)
            .appendingPathComponent("animations")
            .appendingPathComponent(fileName)
    }
    
    static func load(downloadId: UUID, dayKey: String) -> NotebookAnimationManifest {
        let url = manifestURL(downloadId: downloadId, dayKey: dayKey)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(NotebookAnimationManifest.self, from: data) else {
            return .empty
        }
        return manifest
    }
    
    static func save(_ manifest: NotebookAnimationManifest, downloadId: UUID, dayKey: String) throws {
        let dir = PathUtils.notebookDayDirectory(downloadId: downloadId, dayKey: dayKey)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let animationsDir = dir.appendingPathComponent("animations", isDirectory: true)
        try FileManager.default.createDirectory(at: animationsDir, withIntermediateDirectories: true)
        
        let url = manifestURL(downloadId: downloadId, dayKey: dayKey)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }
    
    static func append(
        _ record: NotebookAnimationRecord,
        downloadId: UUID,
        dayKey: String
    ) throws {
        var manifest = load(downloadId: downloadId, dayKey: dayKey)
        manifest.animations.insert(record, at: 0)
        try save(manifest, downloadId: downloadId, dayKey: dayKey)
    }
    
    static func delete(
        record: NotebookAnimationRecord,
        downloadId: UUID,
        dayKey: String
    ) throws {
        var manifest = load(downloadId: downloadId, dayKey: dayKey)
        manifest.animations.removeAll { $0.id == record.id }
        try save(manifest, downloadId: downloadId, dayKey: dayKey)
        
        let videoURL = videoURL(downloadId: downloadId, dayKey: dayKey, fileName: record.videoFileName)
        try? FileManager.default.removeItem(at: videoURL)
    }
    
    static func resolvedVideoURL(
        for record: NotebookAnimationRecord,
        downloadId: UUID,
        dayKey: String
    ) -> URL {
        videoURL(downloadId: downloadId, dayKey: dayKey, fileName: record.videoFileName)
    }
}
