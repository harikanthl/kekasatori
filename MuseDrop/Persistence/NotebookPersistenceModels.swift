//
//  NotebookPersistenceModels.swift
//  MuseDrop
//

import Foundation
import SwiftData

@Model
final class UserNotebookEntryRecord {
    @Attribute(.unique) var id: UUID
    var downloadId: UUID
    var dayKey: String
    var content: String
    var contentRTFData: Data?
    var formattingJSON: String
    var templateRaw: String
    var createdAt: Date
    var updatedAt: Date
    
    var download: DownloadRecord?
    
    init(
        id: UUID = UUID(),
        downloadId: UUID,
        dayKey: String,
        content: String = "",
        contentRTFData: Data? = nil,
        formattingJSON: String = NotebookPageFormatting.default.encodedJSON(),
        templateRaw: String = NotebookPageTemplate.ruled.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.downloadId = downloadId
        self.dayKey = dayKey
        self.content = content
        self.contentRTFData = contentRTFData
        self.formattingJSON = formattingJSON
        self.templateRaw = templateRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    func toEntry() -> UserNotebookEntry {
        UserNotebookEntry(
            id: id,
            downloadId: downloadId,
            dayKey: dayKey,
            content: content,
            richContent: contentRTFData,
            formatting: NotebookPageFormatting.decode(from: formattingJSON),
            template: NotebookPageTemplate.from(raw: templateRaw),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
