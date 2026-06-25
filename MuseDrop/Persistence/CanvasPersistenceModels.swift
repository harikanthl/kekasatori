
//
//  CanvasPersistenceModels.swift
//  MuseDrop
//

import Foundation
import SwiftData

@Model
final class CanvasBoardRecord {
    @Attribute(.unique) var id: UUID
    var downloadId: UUID
    var title: String
    var kindRaw: String
    var sortOrder: Int
    var updatedAt: Date
    var createdAt: Date
    
    var download: DownloadRecord?
    
    init(
        id: UUID = UUID(),
        downloadId: UUID,
        title: String,
        kind: CanvasBoardKind,
        sortOrder: Int? = nil,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.downloadId = downloadId
        self.title = title
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder ?? kind.sortOrder
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
    
    var kind: CanvasBoardKind {
        CanvasBoardKind(rawValue: kindRaw) ?? .custom
    }
    
    func toBoard(hasThumbnail: Bool) -> CanvasBoard {
        CanvasBoard(
            id: id,
            downloadId: downloadId,
            title: title,
            kind: kind,
            sortOrder: sortOrder,
            updatedAt: updatedAt,
            createdAt: createdAt,
            hasThumbnail: hasThumbnail
        )
    }
}
