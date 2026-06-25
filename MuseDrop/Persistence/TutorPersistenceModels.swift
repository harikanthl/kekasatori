//
//  TutorPersistenceModels.swift
//  MuseDrop
//

import Foundation
import SwiftData

@Model
final class TutorConversationRecord {
    @Attribute(.unique) var id: UUID
    var downloadId: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TutorMessageRecord.conversation)
    var messages: [TutorMessageRecord]

    init(id: UUID = UUID(), downloadId: UUID, title: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.downloadId = downloadId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = []
    }
}

@Model
final class TutorMessageRecord {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var conversation: TutorConversationRecord?

    init(id: UUID = UUID(), roleRaw: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.createdAt = createdAt
    }
}
