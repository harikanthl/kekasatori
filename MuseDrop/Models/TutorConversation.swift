//
//  TutorConversation.swift
//  MuseDrop
//

import Foundation

struct TutorMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    var role: LLMRole
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: LLMRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct TutorConversation: Sendable {
    var downloadId: UUID
    var title: String
    var messages: [TutorMessage]
}
