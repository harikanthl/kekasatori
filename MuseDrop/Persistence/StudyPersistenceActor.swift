//
//  StudyPersistenceActor.swift
//  MuseDrop
//
//  Background SwiftData access for study sessions (transcripts, analysis, history).
//

import Foundation
import SwiftData

struct StudyArtifactHistoryItem: Identifiable, Hashable, Sendable {
    var kindRaw: String
    var generatedAt: Date
    var engineRaw: String
    
    var id: String { "\(kindRaw)|\(generatedAt.timeIntervalSince1970)" }
}

actor StudyPersistenceActor {
    private let modelContainer: ModelContainer
    private let logService = LogService.shared
    
    init(container: ModelContainer) {
        self.modelContainer = container
    }
    
    private func makeContext() -> ModelContext {
        ModelContext(modelContainer)
    }
    
    // MARK: - Reads
    
    func loadAnalysis(for downloadId: UUID) -> MediaAnalysis? {
        let context = makeContext()
        guard let download = fetchDownload(id: downloadId, in: context),
              let session = download.studySession else {
            return nil
        }
        return MediaAnalysisMapper.toMediaAnalysis(session, downloadId: downloadId)
    }
    
    func cachedTranscript(for item: DownloadItem) -> MediaTranscript? {
        let context = makeContext()
        guard let download = fetchDownload(id: item.id, in: context) else { return nil }
        return cachedTranscript(for: download, expectedItem: item, in: context)
    }
    
    func cachedTranscript(for downloadId: UUID) -> MediaTranscript? {
        let context = makeContext()
        guard let download = fetchDownload(id: downloadId, in: context) else { return nil }
        return cachedTranscript(for: download, expectedItem: nil, in: context)
    }
    
    func hasCachedTranscript(for item: DownloadItem) -> Bool {
        cachedTranscript(for: item) != nil
    }
    
    func hasCachedTranscript(for downloadId: UUID) -> Bool {
        cachedTranscript(for: downloadId) != nil
    }
    
    func artifactHistory(for downloadId: UUID) -> [StudyArtifactHistoryItem] {
        let context = makeContext()
        guard let session = fetchDownload(id: downloadId, in: context)?.studySession else {
            return []
        }
        return session.artifactHistory
            .sorted { $0.generatedAt > $1.generatedAt }
            .map {
                StudyArtifactHistoryItem(
                    kindRaw: $0.kindRaw,
                    generatedAt: $0.generatedAt,
                    engineRaw: $0.engineRaw
                )
            }
    }
    
    func hasIncompleteStudySession(for downloadId: UUID) -> Bool {
        guard let analysis = loadAnalysis(for: downloadId) else { return false }
        return !Self.isCompleteStudyPack(analysis)
    }
    
    // MARK: - Writes
    //
    // DownloadRecord fields are owned exclusively by the main-context DataStore
    // (the single writer). This actor never inserts or updates DownloadRecord
    // fields; saveAnalysis only links a StudySession to an already-persisted
    // download (a one-time relationship set) and writes the study artifacts.

    func clearStudyPackContent(for downloadId: UUID) {
        let context = makeContext()
        guard let session = fetchDownload(id: downloadId, in: context)?.studySession else { return }
        
        session.summaryOneLine = ""
        session.summaryParagraph = ""
        session.notesTitle = ""
        session.mindMapCentralTopic = ""
        session.summaryBullets.removeAll()
        session.noteSections.removeAll()
        session.flashcards.removeAll()
        session.keyConcepts.removeAll()
        session.mindMapNodes.removeAll()
        session.mindMapEdges.removeAll()
        session.updatedAt = Date()
        save(context)
        logService.info("Cleared study pack content for download \(downloadId); transcript preserved")
    }
    
    @discardableResult
    func saveAnalysis(
        _ analysis: MediaAnalysis,
        artifactKind: AIStudyArtifactKind,
        logHistory: Bool = true
    ) -> Bool {
        let context = makeContext()

        // The download record must already exist (callers upsert it first). Never
        // synthesize a placeholder with an empty url/outputPath: it gets an empty
        // sourceMediaKey forever, collides on the .unique id when the real record
        // is later inserted, and can be auto-pruned by LibraryManager.
        guard let download = fetchDownload(id: analysis.downloadId, in: context) else {
            logService.error("saveAnalysis: no DownloadRecord for \(analysis.downloadId); skipping save")
            return false
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
        
        let mediaKey = MediaSourceIdentity.key(
            downloadURL: download.url,
            outputPath: download.outputPath
        )
        if !mediaKey.isEmpty {
            session.sourceMediaKey = mediaKey
        }
        
        if logHistory {
            logArtifact(kind: artifactKind, engine: analysis.engine, session: session)
        }
        
        save(context)
        return true
    }
    
    func deleteStudySession(for downloadId: UUID) {
        let context = makeContext()
        guard let download = fetchDownload(id: downloadId, in: context),
              let session = download.studySession else { return }
        download.studySession = nil
        context.delete(session)
        save(context)
        logService.info("Deleted study session for download \(downloadId)")
    }
    
    // MARK: - Helpers
    
    static func isCompleteStudyPack(_ analysis: MediaAnalysis) -> Bool {
        !analysis.summary.oneLine.isEmpty
            && !analysis.notes.sections.isEmpty
            && !analysis.flashcards.isEmpty
    }
    
    private func fetchDownload(id: UUID, in context: ModelContext) -> DownloadRecord? {
        var descriptor = FetchDescriptor<DownloadRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    private func cachedTranscript(
        for download: DownloadRecord,
        expectedItem: DownloadItem?,
        in context: ModelContext
    ) -> MediaTranscript? {
        guard let session = download.studySession,
              let transcript = session.transcript else {
            return nil
        }
        
        let trimmed = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return nil }
        
        let expectedKey = MediaSourceIdentity.key(
            downloadURL: download.url,
            outputPath: download.outputPath
        )
        if let expectedItem {
            let itemKey = MediaSourceIdentity.key(for: expectedItem)
            if !expectedKey.isEmpty, !session.sourceMediaKey.isEmpty, session.sourceMediaKey != itemKey {
                logService.warning(
                    "Ignoring cached transcript for \(expectedItem.displayTitle): saved for a different source"
                )
                return nil
            }
            if !MediaSourceIdentity.durationsAreCompatible(
                videoSeconds: expectedItem.durationSeconds,
                transcriptSeconds: transcript.sourceDurationSeconds
            ) {
                logService.warning(
                    "Ignoring cached transcript for \(expectedItem.displayTitle): duration mismatch (video vs transcript metadata)"
                )
                return nil
            }
        } else if !expectedKey.isEmpty, !session.sourceMediaKey.isEmpty, session.sourceMediaKey != expectedKey {
            logService.warning("Ignoring cached transcript for download \(download.id): source media changed")
            return nil
        }
        
        let engine = TranscriptionEngine(rawValue: transcript.engineRaw) ?? .speechRecognizer
        return MediaTranscript(
            text: trimmed,
            createdAt: transcript.createdAt,
            engine: engine,
            coveredSeconds: transcript.coveredSeconds,
            sourceDurationSeconds: transcript.sourceDurationSeconds,
            coverageNote: transcript.coverageNote
        )
    }
    
    private func logArtifact(
        kind: AIStudyArtifactKind,
        engine: AIEngineKind,
        session: StudySessionRecord
    ) {
        let entry = StudyArtifactRecord(
            kindRaw: kind.rawValue,
            engineRaw: engine.rawValue
        )
        entry.studySession = session
        session.artifactHistory.append(entry)
        pruneArtifactHistory(for: session, maxEntries: 24)
    }
    
    private func pruneArtifactHistory(for session: StudySessionRecord, maxEntries: Int) {
        guard session.artifactHistory.count > maxEntries else { return }
        let sorted = session.artifactHistory.sorted { $0.generatedAt > $1.generatedAt }
        let keep = Set(sorted.prefix(maxEntries).map(\.persistentModelID))
        session.artifactHistory.removeAll { !keep.contains($0.persistentModelID) }
    }
    
    private func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logService.error("SwiftData save failed (background study persistence)", error: error)
        }
    }
}
