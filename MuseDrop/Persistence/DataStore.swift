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
                isAudioMedia: mediaItem.isAudioMedia,
                masteryStageRaw: session.masteryStageRaw,
                isPinned: session.isPinned,
                lastStudiedAt: session.lastStudiedAt
            )
        }
    }

    // MARK: - Study pack export (.kekapack)

    /// Assemble an export for a download: its study analysis plus pointers to
    /// any canvas boards and research-paper directories to stage into the
    /// `.kekapack` archive. Only non-empty directories are referenced.
    func makeStudyPackExport(for downloadId: UUID, sourceTitle: String) -> StudyPackExport? {
        guard let download = fetchDownload(id: downloadId),
              let session = download.studySession,
              let analysis = MediaAnalysisMapper.toMediaAnalysis(session, downloadId: downloadId)
        else { return nil }

        var fileSources: [String: URL] = [:]

        var canvasPayloads: [CanvasBoardPayload] = []
        for (index, board) in download.canvasBoards.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            let dir = PathUtils.canvasBoardDirectory(board.id)
            guard Self.directoryHasFiles(dir) else { continue }
            let archivePath = "canvas/\(index)"
            fileSources[archivePath] = dir
            canvasPayloads.append(
                CanvasBoardPayload(
                    title: board.title,
                    kindRaw: board.kindRaw,
                    sortOrder: board.sortOrder,
                    createdAt: board.createdAt,
                    updatedAt: board.updatedAt,
                    directory: archivePath,
                    files: nil
                )
            )
        }

        var paperPayloads: [PaperPayload] = []
        if MediaAnalysisMapper.toDownloadItem(download).isResearchDocument {
            let dir = PathUtils.paperBundleDirectory(itemId: downloadId)
            if Self.directoryHasFiles(dir) {
                let archivePath = "papers/0"
                fileSources[archivePath] = dir
                paperPayloads.append(PaperPayload(directory: archivePath, files: nil))
            }
        }

        let bundle = StudyPackBundle(
            analysis: analysis,
            sourceTitle: sourceTitle.isEmpty ? download.title : sourceTitle,
            sourceURL: download.url.isEmpty ? nil : download.url,
            sourceFormat: download.format.isEmpty ? nil : download.format,
            canvasBoards: canvasPayloads.isEmpty ? nil : canvasPayloads,
            papers: paperPayloads.isEmpty ? nil : paperPayloads
        )
        return StudyPackExport(bundle: bundle, fileSources: fileSources)
    }

    private static func directoryHasFiles(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return !contents.isEmpty
    }

    // MARK: - Study pack import (.kekapack)

    /// Materialize an imported study pack as a fresh download + study session.
    ///
    /// The importer doesn't have the source media — only the study artifacts —
    /// so the new `DownloadRecord` is a stream-only placeholder with no output
    /// file. Fresh UUIDs are minted for both records so re-importing the same
    /// pack adds a copy instead of clobbering an existing one. Returns the new
    /// download id, or nil if the store is degraded/unwritable.
    @discardableResult
    func importStudyPack(_ decoded: DecodedStudyPack) -> UUID? {
        guard !persistenceDegraded else {
            logService.warning("Skipping study pack import: persistence is degraded (in-memory store)")
            return nil
        }

        let bundle = decoded.bundle
        let analysis = bundle.analysis
        let downloadId = UUID()
        let title = bundle.source.title.isEmpty ? analysis.mediaTitle : bundle.source.title

        // A paper bundle carries its own file, so it consumes as a download; a
        // media pack has no local file on the importer's machine, so it's a
        // stream-only placeholder (the study artifacts are what's portable).
        let isPaper = !(bundle.papers?.isEmpty ?? true)
        let download = DownloadRecord(
            id: downloadId,
            url: bundle.source.sourceURL ?? "",
            title: title,
            format: bundle.source.format ?? "",
            statusRaw: DownloadStatus.completed.rawValue,
            consumptionModeRaw: (isPaper ? ConsumptionMode.download : .streamOnly).rawValue
        )
        context.insert(download)

        let session = StudySessionRecord(
            id: UUID(),
            mediaTitle: analysis.mediaTitle,
            engineRaw: analysis.engine.rawValue,
            createdAt: Date()
        )
        session.download = download
        download.studySession = session
        context.insert(session)

        MediaAnalysisMapper.apply(analysis, to: session)

        let entry = StudyArtifactRecord(
            kindRaw: AIStudyArtifactKind.fullPack.rawValue,
            engineRaw: analysis.engine.rawValue
        )
        entry.studySession = session
        session.artifactHistory.append(entry)

        // Restore canvas boards (new record ids; files rewritten under them).
        for payload in bundle.canvasBoards ?? [] {
            let board = CanvasBoardRecord(
                downloadId: downloadId,
                title: payload.title,
                kind: CanvasBoardKind(rawValue: payload.kindRaw) ?? .custom,
                sortOrder: payload.sortOrder,
                updatedAt: payload.updatedAt,
                createdAt: payload.createdAt
            )
            board.download = download
            context.insert(board)
            restorePayload(
                directory: payload.directory,
                legacyBlobs: payload.files,
                root: decoded.rootDirectory,
                to: PathUtils.canvasBoardDirectory(board.id),
                label: "canvas board \"\(payload.title)\""
            )
        }

        // Restore the research-paper bundle under the new download id.
        for payload in bundle.papers ?? [] {
            restorePayload(
                directory: payload.directory,
                legacyBlobs: payload.files,
                root: decoded.rootDirectory,
                to: PathUtils.paperBundleDirectory(itemId: downloadId),
                label: "paper bundle for \"\(title)\""
            )
        }

        saveContext()
        logService.info("Imported study pack \"\(title)\"")
        return downloadId
    }

    /// Restore a payload's files into `destination`: copy from the extracted
    /// archive directory (format 2) or write inline base64 blobs (legacy
    /// format 1). Failures are logged, not fatal.
    private func restorePayload(
        directory: String?,
        legacyBlobs: [FileBlob]?,
        root: URL?,
        to destination: URL,
        label: String
    ) {
        do {
            if let directory, let root {
                let source = root.appendingPathComponent(directory)
                guard FileManager.default.fileExists(atPath: source.path) else { return }
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
            } else if let legacyBlobs {
                try DirectoryArchive.restore(legacyBlobs, to: destination)
            }
        } catch {
            logService.error("Failed restoring \(label)", error: error)
        }
    }

    // MARK: - Study pack organization

    /// Map of source download id → mastery stage, for showing mastery on the
    /// Library grid (whose items are DownloadItems, not study packs).
    func masteryStagesByDownload() -> [UUID: MasteryStage] {
        guard let sessions = try? context.fetch(FetchDescriptor<StudySessionRecord>()) else { return [:] }
        var map: [UUID: MasteryStage] = [:]
        for session in sessions {
            guard let raw = session.masteryStageRaw,
                  let stage = MasteryStage(rawValue: raw),
                  let id = session.download?.id else { continue }
            map[id] = stage
        }
        return map
    }

    private func fetchSession(id: UUID) -> StudySessionRecord? {
        var descriptor = FetchDescriptor<StudySessionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Set (or clear, with nil) a pack's Shu-Ha-Ri mastery stage.
    func setMasteryStage(_ stage: MasteryStage?, forSession sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.masteryStageRaw = stage?.rawValue
        try? context.save()
    }

    func setPinned(_ pinned: Bool, forSession sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.isPinned = pinned
        try? context.save()
    }

    /// Stamp the pack as studied now (drives the "recently studied" sort).
    func markStudied(sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.lastStudiedAt = Date()
        try? context.save()
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
