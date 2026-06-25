//
//  TutorPersistenceActor.swift
//  MuseDrop
//
//  Background SwiftData access for tutor conversations (one thread per item).
//

import Foundation
import SwiftData

actor TutorPersistenceActor {
    private let modelContainer: ModelContainer
    private let logService = LogService.shared

    init(container: ModelContainer) {
        self.modelContainer = container
    }

    private func makeContext() -> ModelContext { ModelContext(modelContainer) }

    private func fetchRecord(for downloadId: UUID, in context: ModelContext) -> TutorConversationRecord? {
        var descriptor = FetchDescriptor<TutorConversationRecord>(
            predicate: #Predicate { $0.downloadId == downloadId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Load the conversation for an item (empty messages if none yet).
    func conversation(for downloadId: UUID) -> TutorConversation {
        let context = makeContext()
        guard let record = fetchRecord(for: downloadId, in: context) else {
            return TutorConversation(downloadId: downloadId, title: "Tutor", messages: [])
        }
        let messages = record.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { TutorMessage(id: $0.id, role: LLMRole(rawValue: $0.roleRaw) ?? .assistant,
                                content: $0.content, createdAt: $0.createdAt) }
        return TutorConversation(downloadId: downloadId, title: record.title, messages: messages)
    }

    /// Append a message, creating the conversation on first use.
    func append(_ message: TutorMessage, downloadId: UUID, title: String) {
        let context = makeContext()
        let record = fetchRecord(for: downloadId, in: context) ?? {
            let created = TutorConversationRecord(downloadId: downloadId, title: title)
            context.insert(created)
            return created
        }()
        let msg = TutorMessageRecord(id: message.id, roleRaw: message.role.rawValue,
                                     content: message.content, createdAt: message.createdAt)
        msg.conversation = record
        record.messages.append(msg)
        record.updatedAt = Date()
        save(context)
    }

    /// Replace the content of an existing message (used while streaming).
    func updateMessage(id: UUID, content: String, downloadId: UUID) {
        let context = makeContext()
        guard let record = fetchRecord(for: downloadId, in: context),
              let msg = record.messages.first(where: { $0.id == id }) else { return }
        msg.content = content
        record.updatedAt = Date()
        save(context)
    }

    func clear(downloadId: UUID) {
        let context = makeContext()
        guard let record = fetchRecord(for: downloadId, in: context) else { return }
        context.delete(record)
        save(context)
    }

    private func save(_ context: ModelContext) {
        do { try context.save() }
        catch { logService.error("Tutor save failed", error: error) }
    }
}
