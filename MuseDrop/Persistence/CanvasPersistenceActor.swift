//
//  CanvasPersistenceActor.swift
//  MuseDrop
//

import Foundation
import SwiftData

actor CanvasPersistenceActor {
    private let modelContainer: ModelContainer
    private let logService = LogService.shared
    
    init(container: ModelContainer) {
        self.modelContainer = container
    }
    
    private func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }
    
    // MARK: - Boards
    
    func firstThumbnailURL(for downloadId: UUID) -> URL? {
        for board in boards(for: downloadId) {
            let url = PathUtils.canvasThumbnailFile(board.id)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
    
    func boards(for downloadId: UUID) -> [CanvasBoard] {
        let context = makeContext()
        let descriptor = FetchDescriptor<CanvasBoardRecord>(
            predicate: #Predicate { $0.downloadId == downloadId },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map { record in
            let hasThumb = FileManager.default.fileExists(atPath: PathUtils.canvasThumbnailFile(record.id).path)
            return record.toBoard(hasThumbnail: hasThumb)
        }
    }
    
    @discardableResult
    func ensureDefaultBoards(for downloadId: UUID) -> [CanvasBoard] {
        let existing = boards(for: downloadId)
        guard existing.isEmpty else { return existing }
        
        let context = makeContext()
        guard let download = fetchDownload(id: downloadId, in: context) else {
            logService.error("ensureDefaultBoards: no DownloadRecord for \(downloadId); skipping board creation")
            return []
        }
        let defaults: [CanvasBoardKind] = [.overview, .deepDive, .questions]
        var created: [CanvasBoard] = []

        for kind in defaults {
            let record = CanvasBoardRecord(downloadId: downloadId, title: kind.defaultTitle, kind: kind)
            record.download = download
            context.insert(record)
            try? FileManager.default.createDirectory(
                at: PathUtils.canvasBoardDirectory(record.id),
                withIntermediateDirectories: true
            )
            created.append(record.toBoard(hasThumbnail: false))
        }
        
        save(context)
        return created
    }
    
    func createBoard(downloadId: UUID, title: String) -> CanvasBoard? {
        let context = makeContext()
        guard let download = fetchDownload(id: downloadId, in: context) else {
            logService.error("createBoard: no DownloadRecord for \(downloadId); skipping board creation")
            return nil
        }
        let record = CanvasBoardRecord(
            downloadId: downloadId,
            title: title,
            kind: .custom,
            sortOrder: boards(for: downloadId).count
        )
        record.download = download
        context.insert(record)
        try? FileManager.default.createDirectory(
            at: PathUtils.canvasBoardDirectory(record.id),
            withIntermediateDirectories: true
        )
        save(context)
        return record.toBoard(hasThumbnail: false)
    }
    
    func deleteBoard(_ boardId: UUID) {
        let context = makeContext()
        guard let record = fetchBoard(id: boardId, in: context) else { return }
        context.delete(record)
        save(context)
        try? FileManager.default.removeItem(at: PathUtils.canvasBoardDirectory(boardId))
    }
    
    // MARK: - Scene I/O
    
    func loadSceneJSON(for boardId: UUID) -> String? {
        let sceneURL = PathUtils.canvasSceneFile(boardId)
        guard FileManager.default.fileExists(atPath: sceneURL.path),
              let raw = try? String(contentsOf: sceneURL, encoding: .utf8) else {
            return nil
        }
        return hydrateSceneJSON(raw, boardId: boardId)
    }
    
    func saveScene(boardId: UUID, sceneJSON: String) {
        let context = makeContext()
        guard let record = fetchBoard(id: boardId, in: context) else { return }
        
        do {
            let portable = try extractFilesToDisk(sceneJSON: sceneJSON, boardId: boardId)
            let sceneURL = PathUtils.canvasSceneFile(boardId)
            try FileManager.default.createDirectory(
                at: sceneURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try portable.write(to: sceneURL, atomically: true, encoding: .utf8)
            record.updatedAt = Date()
            save(context)
        } catch {
            logService.error("Failed to save canvas scene", error: error)
        }
    }
    
    func saveThumbnail(boardId: UUID, pngData: Data) {
        let url = PathUtils.canvasThumbnailFile(boardId)
        try? pngData.write(to: url)
    }
    
    func thumbnailData(for boardId: UUID) -> Data? {
        let url = PathUtils.canvasThumbnailFile(boardId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }
    
    func importImageFile(boardId: UUID, sourceURL: URL, fileId: String) throws -> String {
        let filesDir = PathUtils.canvasFilesDirectory(boardId)
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let dest = filesDir.appendingPathComponent("\(fileId).\(ext)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest.lastPathComponent
    }
    
    // MARK: - Private
    
    private func fetchDownload(id: UUID, in context: ModelContext) -> DownloadRecord? {
        var descriptor = FetchDescriptor<DownloadRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    private func fetchBoard(id: UUID, in context: ModelContext) -> CanvasBoardRecord? {
        var descriptor = FetchDescriptor<CanvasBoardRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logService.error("Canvas SwiftData save failed", error: error)
        }
    }
    
    private func extractFilesToDisk(sceneJSON: String, boardId: UUID) throws -> String {
        guard let data = sceneJSON.data(using: .utf8),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return sceneJSON
        }
        
        guard var files = root["files"] as? [String: [String: Any]] else {
            return sceneJSON
        }
        
        let filesDir = PathUtils.canvasFilesDirectory(boardId)
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        
        for (fileId, var meta) in files {
            if let dataURL = meta["dataURL"] as? String,
               let binary = Self.decodeDataURL(dataURL) {
                let ext = Self.fileExtension(for: meta["mimeType"] as? String)
                let filename = "\(fileId).\(ext)"
                let dest = filesDir.appendingPathComponent(filename)
                try binary.write(to: dest)
                meta.removeValue(forKey: "dataURL")
                meta["storagePath"] = filename
                files[fileId] = meta
            }
        }
        
        root["files"] = files
        let out = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        return String(decoding: out, as: UTF8.self)
    }
    
    private func hydrateSceneJSON(_ raw: String, boardId: UUID) -> String {
        guard let data = raw.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var files = root["files"] as? [String: [String: Any]] else {
            return raw
        }
        
        let filesDir = PathUtils.canvasFilesDirectory(boardId)
        for (fileId, var meta) in files {
            if meta["dataURL"] != nil { continue }
            let filename = (meta["storagePath"] as? String) ?? "\(fileId).png"
            let fileURL = filesDir.appendingPathComponent(filename)
            guard let binary = try? Data(contentsOf: fileURL) else { continue }
            let mime = (meta["mimeType"] as? String) ?? "image/png"
            meta["dataURL"] = "data:\(mime);base64,\(binary.base64EncodedString())"
            files[fileId] = meta
        }
        
        root["files"] = files
        guard let out = try? JSONSerialization.data(withJSONObject: root) else { return raw }
        return String(decoding: out, as: UTF8.self)
    }
    
    private static func decodeDataURL(_ dataURL: String) -> Data? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: comma)...])
        return Data(base64Encoded: base64)
    }
    
    private static func fileExtension(for mimeType: String?) -> String {
        switch mimeType {
        case "image/jpeg": return "jpg"
        case "image/webp": return "webp"
        case "image/gif": return "gif"
        case "image/svg+xml": return "svg"
        default: return "png"
        }
    }
}
