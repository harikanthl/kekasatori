//
//  DataStore.swift
//  MuseDrop
//
//  SwiftData persistence layer with legacy JSON migration.
//

import Foundation
import SwiftData

@MainActor
final class DataStore {
    static let shared = DataStore()
    
    let modelContainer: ModelContainer
    let studyPersistence: StudyPersistenceActor
    let canvasPersistence: CanvasPersistenceActor
    let notebookPersistence: NotebookPersistenceActor
    let tutorPersistence: TutorPersistenceActor
    private let logService = LogService.shared
    private let migrationKey = "swiftdata.migration.completed"
    private let sourceMediaKeyBackfillKey = "swiftdata.backfill.sourceMediaKey.done"

    /// True when the on-disk store could not be opened (even after recovery) and
    /// we fell back to a temporary in-memory database — the app still launches,
    /// but data won't persist this session. The UI surfaces a warning.
    private(set) var persistenceDegraded = false
    
    private init() {
        do {
            try PathUtils.ensureDirectoriesExist()
            modelContainer = try Self.openContainer()
            studyPersistence = StudyPersistenceActor(container: modelContainer)
            canvasPersistence = CanvasPersistenceActor(container: modelContainer)
            notebookPersistence = NotebookPersistenceActor(container: modelContainer)
            tutorPersistence = TutorPersistenceActor(container: modelContainer)
            backfillSourceMediaKeysIfNeeded()
            migrateLegacyDataIfNeeded()
        } catch {
            logService.error("SwiftData load failed — backing up store and creating a fresh database", error: error)
            Self.backupCorruptedStore()
            do {
            modelContainer = try Self.openContainer()
            studyPersistence = StudyPersistenceActor(container: modelContainer)
            canvasPersistence = CanvasPersistenceActor(container: modelContainer)
            notebookPersistence = NotebookPersistenceActor(container: modelContainer)
            tutorPersistence = TutorPersistenceActor(container: modelContainer)
            migrateLegacyDataIfNeeded()
            } catch {
                // Disk is unwritable/full even after backup. Don't crash — fall
                // back to a temporary in-memory store so the app still launches;
                // the UI shows a "library couldn't be opened" warning.
                logService.error("Reopen after recovery failed; using a temporary in-memory database", error: error)
                persistenceDegraded = true
                guard let memory = try? Self.openInMemoryContainer() else {
                    fatalError("Failed to create even an in-memory SwiftData container: \(error)")
                }
                modelContainer = memory
                studyPersistence = StudyPersistenceActor(container: modelContainer)
                canvasPersistence = CanvasPersistenceActor(container: modelContainer)
                notebookPersistence = NotebookPersistenceActor(container: modelContainer)
                tutorPersistence = TutorPersistenceActor(container: modelContainer)
            }
        }
    }
    
    private static func makeSchema() -> Schema {
        Schema([
            DownloadRecord.self,
            StudySessionRecord.self,
            TranscriptRecord.self,
            StudyArtifactRecord.self,
            OrderedTextRecord.self,
            NoteSectionRecord.self,
            FlashcardRecord.self,
            KeyConceptRecord.self,
            MindMapNodeRecord.self,
            MindMapEdgeRecord.self,
            CanvasBoardRecord.self,
            UserNotebookEntryRecord.self,
            TutorConversationRecord.self,
            TutorMessageRecord.self
        ])
    }

    private static func openContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            url: PathUtils.swiftDataStoreURL,
            allowsSave: true
        )
        return try ModelContainer(for: makeSchema(), configurations: [configuration])
    }

    /// Last-resort container that keeps the app usable when the on-disk store
    /// can't be opened (e.g. unwritable directory, full disk). Not persisted.
    private static func openInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: makeSchema(), configurations: [configuration])
    }
    
    private static func backupCorruptedStore() {
        let storeURL = PathUtils.swiftDataStoreURL
        let backupURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Kekasatori.store.backup-\(Int(Date().timeIntervalSince1970))")
        
        let fm = FileManager.default
        if fm.fileExists(atPath: storeURL.path) {
            try? fm.moveItem(at: storeURL, to: backupURL)
        }
        
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try? fm.removeItem(at: sidecar)
            }
        }
    }
    
    /// Fills sourceMediaKey for sessions created before the field existed.
    /// One-time: gated behind a UserDefaults flag and scoped to rows still missing a key.
    private func backfillSourceMediaKeysIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: sourceMediaKeyBackfillKey) else { return }

        let descriptor = FetchDescriptor<StudySessionRecord>(
            predicate: #Predicate { $0.sourceMediaKey == "" }
        )
        guard let sessions = try? context.fetch(descriptor) else { return }

        var updated = 0
        for session in sessions where session.sourceMediaKey.isEmpty {
            guard let download = session.download else { continue }
            let key = MediaSourceIdentity.key(
                downloadURL: download.url,
                outputPath: download.outputPath
            )
            guard !key.isEmpty else { continue }
            session.sourceMediaKey = key
            updated += 1
        }

        if updated > 0 {
            saveContext()
            logService.info("Backfilled sourceMediaKey for \(updated) study sessions")
        }

        UserDefaults.standard.set(true, forKey: sourceMediaKeyBackfillKey)
    }
    
    private var context: ModelContext {
        modelContainer.mainContext
    }
    
    // MARK: - Downloads
    
    func fetchAllDownloads() -> [DownloadItem] {
        let descriptor = FetchDescriptor<DownloadRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        guard let records = try? context.fetch(descriptor) else { return [] }
        return records.map { MediaAnalysisMapper.toDownloadItem($0) }
    }
    
    func fetchDownload(id: UUID) -> DownloadRecord? {
        var descriptor = FetchDescriptor<DownloadRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    func upsertDownload(_ item: DownloadItem) {
        if let record = fetchDownload(id: item.id) {
            MediaAnalysisMapper.apply(item, to: record)
        } else {
            context.insert(MediaAnalysisMapper.makeDownloadRecord(from: item))
        }
        saveContext()
    }
    
    func removeDownload(id: UUID) {
        guard let record = fetchDownload(id: id) else { return }
        context.delete(record)
        saveContext()
    }
    
    // MARK: - Study sessions (main-context reads for library UI only)
    
    func loadAnalysis(for downloadId: UUID) -> MediaAnalysis? {
        guard let download = fetchDownload(id: downloadId),
              let session = download.studySession else {
            return nil
        }
        return MediaAnalysisMapper.toMediaAnalysis(session, downloadId: downloadId)
    }
    
    func fetchAllStudyPackSummaries() -> [StudyPackSummary] {
        let descriptor = FetchDescriptor<StudySessionRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        guard let sessions = try? context.fetch(descriptor) else { return [] }
        
        return sessions.compactMap { session in
            guard let download = session.download else { return nil }
            
            let hasTranscript = (session.transcript?.text.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 80
            let hasPackContent = !session.summaryOneLine.isEmpty
                || !session.flashcards.isEmpty
                || !session.noteSections.isEmpty
            
            guard hasTranscript || hasPackContent else { return nil }
            
            let isComplete = !session.summaryOneLine.isEmpty
                && !session.noteSections.isEmpty
                && !session.flashcards.isEmpty
            
            let history = session.artifactHistory.sorted { $0.generatedAt > $1.generatedAt }
            let latest = history.first

            // Derive media-type flags via the same mapping the Library uses so the
            // two screens classify Papers / Audio / Video identically.
            let mediaItem = MediaAnalysisMapper.toDownloadItem(download)

            return StudyPackSummary(
                downloadId: download.id,
                sessionId: session.id,
                mediaTitle: session.mediaTitle.isEmpty ? download.title : session.mediaTitle,
                summaryOneLine: session.summaryOneLine,
                thumbnailPath: download.thumbnailPath,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                engineRaw: session.engineRaw,
                isCompletePack: isComplete,
                hasTranscript: hasTranscript,
                flashcardCount: session.flashcards.count,
                noteSectionCount: session.noteSections.count,
                conceptCount: session.keyConcepts.count,
                generationCount: history.count,
                lastGeneratedAt: latest?.generatedAt,
                lastArtifactKindRaw: latest?.kindRaw,
                isStreamOnly: download.consumptionModeRaw == ConsumptionMode.streamOnly.rawValue,
                isResearchDocument: mediaItem.isResearchDocument,
                isAudioMedia: mediaItem.isAudioMedia
            )
        }
    }
    
    func markStudyAvailable(for downloadId: UUID) {
        // Intentionally a no-op: study content is persisted by the background
        // StudyPersistenceActor, so there is nothing dirty on the main context to
        // save here. Kept (rather than removed) because the call site lives in
        // LibraryManager, which is owned elsewhere.
    }
    
    // MARK: - Migration
    
    private func migrateLegacyDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        
        logService.info("Migrating legacy JSON data into SwiftData…")
        let downloadsMigrated = migrateDownloadsJSON()
        migrateAnalysisJSONFiles()   // best-effort; regenerable

        // Only mark migration complete when the critical downloads data was
        // provably handled. If the legacy file existed but couldn't be read or
        // decoded, defer so we retry next launch instead of silently losing it.
        guard downloadsMigrated else {
            logService.error("Legacy downloads migration deferred; will retry on next launch")
            return
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        saveContext()
        logService.info("SwiftData migration complete")
    }

    /// Returns true when there was nothing to migrate or migration succeeded;
    /// false only when an existing legacy file could not be read/decoded.
    @discardableResult
    private func migrateDownloadsJSON() -> Bool {
        let url = PathUtils.downloadsJSONPath
        guard FileManager.default.fileExists(atPath: url.path) else {
            return true   // nothing to migrate
        }

        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            logService.error("Failed to read/decode legacy downloads.json; deferring migration")
            return false
        }

        // Insert/apply all items without saving per item, then save once.
        for item in items {
            if let record = fetchDownload(id: item.id) {
                MediaAnalysisMapper.apply(item, to: record)
            } else {
                context.insert(MediaAnalysisMapper.makeDownloadRecord(from: item))
            }
        }
        saveContext()

        logService.info("Migrated \(items.count) downloads from JSON")
        return true
    }
    
    private func migrateAnalysisJSONFiles() {
        let directory = PathUtils.analysisDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        
        var migrated = 0
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let analysis = try? JSONDecoder().decode(MediaAnalysis.self, from: data) else {
                continue
            }
            saveAnalysisForMigration(analysis, artifactKind: .fullPack)
            migrated += 1
        }
        
        if migrated > 0 {
            saveContext()
            logService.info("Migrated \(migrated) AI analysis files into SwiftData")
        }
    }
    
    private func saveAnalysisForMigration(
        _ analysis: MediaAnalysis,
        artifactKind: AIStudyArtifactKind
    ) {
        // Skip analyses with no matching download rather than synthesizing an
        // empty-url placeholder (which would later be auto-pruned, cascade-
        // deleting this very session). The legacy JSON stays on disk.
        guard let download = fetchDownload(id: analysis.downloadId) else {
            logService.warning("Skipping legacy analysis with no matching download (\(analysis.downloadId))")
            return
        }

        let session: StudySessionRecord
        if let existing = download.studySession {
            session = existing
        } else {
            let created = StudySessionRecord(
                id: analysis.id,
                mediaTitle: analysis.mediaTitle,
                engineRaw: analysis.engine.rawValue,
                createdAt: analysis.createdAt
            )
            created.download = download
            download.studySession = created
            context.insert(created)
            session = created
        }
        
        MediaAnalysisMapper.apply(analysis, to: session)
        let entry = StudyArtifactRecord(
            kindRaw: artifactKind.rawValue,
            engineRaw: analysis.engine.rawValue
        )
        entry.studySession = session
        session.artifactHistory.append(entry)
        // Caller (migrateAnalysisJSONFiles) saves once after the whole loop.
    }
    
    private func saveContext() {
        do {
            try context.save()
        } catch {
            logService.error("SwiftData save failed", error: error)
        }
    }
}
