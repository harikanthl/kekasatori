//
//  NotebookPersistenceActor.swift
//  MuseDrop
//

import Foundation
import SwiftData

actor NotebookPersistenceActor {
    private let modelContainer: ModelContainer
    private let logService = LogService.shared
    
    init(container: ModelContainer) {
        self.modelContainer = container
    }
    
    private func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }
    
    func entries(for downloadId: UUID) -> [UserNotebookEntry] {
        let context = makeContext()
        let descriptor = FetchDescriptor<UserNotebookEntryRecord>(
            predicate: #Predicate { $0.downloadId == downloadId },
            sortBy: [SortDescriptor(\.dayKey, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map { $0.toEntry() }
    }
    
    func entry(for downloadId: UUID, dayKey: String) -> UserNotebookEntry? {
        let context = makeContext()
        guard let record = fetchEntry(downloadId: downloadId, dayKey: dayKey, in: context) else {
            return nil
        }
        return record.toEntry()
    }
    
    @discardableResult
    func saveEntry(
        downloadId: UUID,
        dayKey: String,
        content: String,
        richContent: Data?,
        formattingJSON: String,
        templateRaw: String
    ) -> UserNotebookEntry? {
        let context = makeContext()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRichContent = richContent != nil && !(richContent?.isEmpty ?? true)
        let keepsEmptyPage = templateRaw != NotebookPageTemplate.ruled.rawValue
            || hasRichContent
            || NotebookPageFormatting.decode(from: formattingJSON) != .default
        
        if let existing = fetchEntry(downloadId: downloadId, dayKey: dayKey, in: context) {
            if trimmed.isEmpty, !hasRichContent, !keepsEmptyPage {
                context.delete(existing)
                save(context)
                return nil
            }
            existing.content = content
            existing.contentRTFData = richContent
            existing.formattingJSON = formattingJSON
            existing.templateRaw = templateRaw
            existing.updatedAt = Date()
            save(context)
            return existing.toEntry()
        }
        
        guard !trimmed.isEmpty || hasRichContent || keepsEmptyPage else { return nil }

        guard let download = fetchDownload(id: downloadId, in: context) else {
            logService.error("saveEntry: no DownloadRecord for \(downloadId); skipping notebook entry insert")
            return nil
        }

        let record = UserNotebookEntryRecord(
            downloadId: downloadId,
            dayKey: dayKey,
            content: content,
            contentRTFData: richContent,
            formattingJSON: formattingJSON,
            templateRaw: templateRaw
        )
        record.download = download
        context.insert(record)
        save(context)
        return record.toEntry()
    }
    
    func deleteEntry(id: UUID) {
        let context = makeContext()
        var descriptor = FetchDescriptor<UserNotebookEntryRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try? context.fetch(descriptor).first else { return }
        context.delete(record)
        save(context)
    }
    
    // MARK: - Private
    
    private func fetchEntry(
        downloadId: UUID,
        dayKey: String,
        in context: ModelContext
    ) -> UserNotebookEntryRecord? {
        var descriptor = FetchDescriptor<UserNotebookEntryRecord>(
            predicate: #Predicate { record in
                record.downloadId == downloadId && record.dayKey == dayKey
            }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    private func fetchDownload(id: UUID, in context: ModelContext) -> DownloadRecord? {
        var descriptor = FetchDescriptor<DownloadRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logService.error("Notebook SwiftData save failed", error: error)
        }
    }
}
