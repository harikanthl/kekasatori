//
//  PlaylistImportViewModel.swift
//  MuseDrop
//
//  Orchestrates a YouTube playlist import: enumerate (PlaylistImportService) →
//  add each video as a stream-only library item (collection appears fast) →
//  transcribe each one-by-one (captions fast; captionless full on-device). All
//  items share one playlistId so the Library can group them. Cancellable;
//  per-item failures are isolated so one bad video can't sink the batch.
//

import Foundation
import Combine

@MainActor
final class PlaylistImportViewModel: ObservableObject {
    struct ImportFailure: Identifiable {
        let id = UUID()
        let title: String
        let reason: String
    }

    enum Stage: Equatable { case idle, loading, ready, running, finished }

    @Published var stage: Stage = .idle
    @Published var playlistTitle = ""
    @Published var entries: [PlaylistEntry] = []
    /// How many videos to import (defaults to all once loaded).
    @Published var limit: Int = 0
    @Published var kind: StreamMediaKind = .video

    @Published var importedCount = 0
    @Published var transcribedCount = 0
    @Published var currentTitle = ""
    @Published var failures: [ImportFailure] = []
    @Published var errorMessage: String?

    private var sourceURL = ""
    private var job: Task<Void, Never>?
    private var activeSession: UUID?

    var totalToImport: Int { entries.isEmpty ? 0 : min(max(limit, 1), entries.count) }
    var isRunning: Bool { stage == .running }

    /// Enumerate the playlist for the preview step.
    func load(playlistURL: String) {
        sourceURL = playlistURL
        stage = .loading
        errorMessage = nil
        Task {
            do {
                let info = try await PlaylistImportService.enumerate(playlistURL: playlistURL)
                playlistTitle = info.title
                entries = info.entries
                limit = info.entries.count
                stage = .ready
            } catch {
                errorMessage = error.localizedDescription
                stage = .idle
            }
        }
    }

    /// Import the chosen videos, then transcribe them one by one.
    func startImport() {
        guard stage == .ready, !entries.isEmpty else { return }
        let chosen = Array(entries.prefix(totalToImport))
        let playlistId = UUID()
        let title = playlistTitle
        let mediaKind = kind

        importedCount = 0
        transcribedCount = 0
        failures = []
        currentTitle = ""
        stage = .running

        // The VM is @MainActor, so this Task runs on the main actor; the awaits
        // below suspend (network / actor calls) rather than block the UI.
        job = Task { [weak self] in
            guard let self else { return }
            let store = DataStore.shared.studyPersistence

            // Phase A — import as stream-only items (collection shows up in Library).
            var imported: [DownloadItem] = []
            for entry in chosen {
                if Task.isCancelled { break }
                self.currentTitle = entry.title
                do {
                    let item = try await StreamLibraryService.shared.addStreamItem(
                        url: entry.watchURL,
                        kind: mediaKind,
                        playlistId: playlistId,
                        playlistTitle: title
                    )
                    imported.append(item)
                    self.importedCount += 1
                } catch {
                    self.failures.append(.init(title: entry.title, reason: error.localizedDescription))
                }
            }

            // Phase B — transcribe sequentially. Captioned videos are fast;
            // captionless transcribe in full on-device (slower).
            for item in imported {
                if Task.isCancelled { break }
                self.currentTitle = item.displayTitle
                if await store.hasCachedTranscript(for: item) {
                    self.transcribedCount += 1
                    continue
                }
                let session = UUID()
                self.activeSession = session
                await StudyGenerationCoordinator.shared.begin(session: session)
                do {
                    let transcript = try await TranscriptService.shared.transcribeFromSourceURL(
                        item.url,
                        mediaKind: item.streamMediaKind ?? mediaKind,
                        durationSeconds: item.durationSeconds,
                        fullLength: true,
                        session: session
                    )
                    let partial = MediaAnalysis(
                        downloadId: item.id,
                        mediaTitle: item.displayTitle,
                        transcript: transcript,
                        summary: SummaryResult(),
                        engine: .naturalLanguageFallback
                    )
                    await store.saveAnalysis(partial, artifactKind: .transcript)
                    self.transcribedCount += 1
                } catch {
                    self.failures.append(.init(title: item.displayTitle, reason: error.localizedDescription))
                }
            }

            self.activeSession = nil
            self.currentTitle = ""
            self.stage = .finished
        }
    }

    func cancel() {
        job?.cancel()
        if let session = activeSession {
            Task { await StudyGenerationCoordinator.shared.cancel(session: session) }
        }
        stage = .finished
    }

    /// Reset for a fresh import (sheet dismissed / reopened).
    func reset() {
        job?.cancel()
        stage = .idle
        entries = []
        playlistTitle = ""
        importedCount = 0
        transcribedCount = 0
        currentTitle = ""
        failures = []
        errorMessage = nil
    }
}
