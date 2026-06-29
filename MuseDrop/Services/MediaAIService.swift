//
//  MediaAIService.swift
//  MuseDrop
//

import Foundation

enum MediaAIError: LocalizedError {
    case foundationModelsUnavailable(String)
    case analysisFailed(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .foundationModelsUnavailable(let message):
            return message
        case .analysisFailed(let message):
            return message
        case .cancelled:
            return "Study pack generation was stopped."
        }
    }
}

final class MediaAIService: Sendable {
    static let shared = MediaAIService()
    
    private let transcriptService = TranscriptService.shared
    private let logService = LogService.shared
    
    private init() {}
    
    private func persistence() async -> StudyPersistenceActor {
        await MainActor.run { DataStore.shared.studyPersistence }
    }
    
    var engineDescription: String {
        let transcription = TranscriptService.shared.activeEngineDescription
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), FoundationModelBridge.isAvailable {
            return "\(transcription) + Apple Foundation Models"
        }
        #endif
        return "\(transcription) + NaturalLanguage fallback"
    }
    
    func loadSavedTranscript(for item: DownloadItem) async -> MediaTranscript? {
        await persistence().cachedTranscript(for: item)
    }
    
    func foundationModelsStatusMessage() -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelBridge.availabilityMessage
        }
        #endif
        return "Requires macOS 26+ with Apple Intelligence."
    }
    
    func hasSavedTranscript(for item: DownloadItem) async -> Bool {
        await persistence().hasCachedTranscript(for: item)
    }
    
    func loadCachedAnalysis(for item: DownloadItem) async -> MediaAnalysis? {
        guard let analysis = await persistence().loadAnalysis(for: item.id) else { return nil }
        return Self.isCompletePack(analysis) ? analysis : nil
    }
    
    func generateAnalysis(
        for item: DownloadItem,
        forceRegenerate: Bool = false,
        forceRetranscribe: Bool = false,
        session: UUID,
        onProgress: TranscriptService.ProgressHandler? = nil,
        onPartial: (@Sendable (MediaAnalysis) -> Void)? = nil
    ) async throws -> MediaAnalysis {
        let store = await persistence()
        
        try await checkGenerationState(session: session)
        // DownloadRecord fields have a single writer: the main-context DataStore.
        // Ensure the record exists here (committed to the store) before the study
        // actor links a session to it in its own background context.
        await DataStore.shared.upsertDownload(item)

        if !forceRegenerate,
           let cached = await store.loadAnalysis(for: item.id),
           Self.isCompletePack(cached) {
            logService.info("Loaded cached study pack for \(item.displayTitle)")
            return cached
        }
        
        let (transcript, transcriptWasCached) = try await obtainTranscript(
            for: item,
            forceRetranscribe: forceRetranscribe,
            session: session,
            store: store,
            onProgress: onProgress
        )

        // Proactively warm the Tutor's RAG index so chat is grounded immediately
        // (idempotent — RAGIndexService skips unchanged content).
        let ragText = transcript.text
        let ragItemId = item.id
        Task.detached { await RAGIndexService.shared.ingest(downloadId: ragItemId, text: ragText) }
        
        if !transcriptWasCached {
            let partial = MediaAnalysis(
                downloadId: item.id,
                mediaTitle: item.displayTitle,
                transcript: transcript,
                summary: SummaryResult(),
                engine: .naturalLanguageFallback
            )
            await store.saveAnalysis(partial, artifactKind: .transcript)
        } else {
            await store.clearStudyPackContent(for: item.id)
            logService.info(
                "Reusing saved transcript for \(item.displayTitle) (\(transcript.text.count) chars) — no new download"
            )
        }
        
        try await checkGenerationState(session: session)
        onProgress?(TranscriptProgress(
            phase: .finishing,
            detail: transcriptWasCached
                ? "Generating new study materials from saved transcript…"
                : "Generating study materials…"
        ))
        await Task.yield()
        
        let payload = try await analyzeTranscript(
            transcript.text,
            title: item.displayTitle,
            forceRegenerate: forceRegenerate,
            session: session,
            onProgress: onProgress,
            onPartial: { partial in
                onPartial?(MediaAnalysis(
                    downloadId: item.id,
                    mediaTitle: item.displayTitle,
                    transcript: transcript,
                    summary: partial.summary,
                    notes: partial.notes,
                    keyConcepts: partial.keyConcepts,
                    flashcards: partial.flashcards,
                    mindMap: partial.mindMap,
                    engine: partial.engine
                ))
            }
        )
        
        try await checkGenerationState(session: session)
        let analysis = MediaAnalysis(
            downloadId: item.id,
            mediaTitle: item.displayTitle,
            transcript: transcript,
            summary: payload.summary,
            notes: payload.notes,
            keyConcepts: payload.keyConcepts,
            flashcards: payload.flashcards,
            mindMap: payload.mindMap,
            engine: payload.engine
        )
        
        let artifactKind: AIStudyArtifactKind = (forceRegenerate && transcriptWasCached)
            ? .regenerated
            : .fullPack
        await store.saveAnalysis(
            analysis,
            artifactKind: artifactKind,
            logHistory: true
        )
        
        if transcriptWasCached {
            logService.info("Replaced study pack using saved transcript via \(payload.engine.rawValue)")
        } else {
            logService.info("Saved new study pack and transcript using \(payload.engine.rawValue)")
        }
        return analysis
    }
    
    func generateSummary(for mediaURL: URL, downloadId: UUID? = nil) async throws -> SummaryResult {
        let store = await persistence()
        
        if let downloadId,
           let cached = await store.loadAnalysis(for: downloadId),
           Self.isCompletePack(cached) {
            return cached.summary
        }
        
        let transcript: MediaTranscript
        if let downloadId, let cachedTranscript = await store.cachedTranscript(for: downloadId) {
            logService.info("Reusing saved transcript for summary")
            transcript = cachedTranscript
        } else {
            transcript = try await transcriptService.transcribeMedia(at: mediaURL)
        }
        
        let payload = try await analyzeTranscript(
            transcript.text,
            title: mediaURL.deletingPathExtension().lastPathComponent,
            forceRegenerate: false,
            session: nil
        )
        
        if let downloadId {
            let analysis = MediaAnalysis(
                downloadId: downloadId,
                mediaTitle: mediaURL.deletingPathExtension().lastPathComponent,
                transcript: transcript,
                summary: payload.summary,
                notes: payload.notes,
                keyConcepts: payload.keyConcepts,
                flashcards: payload.flashcards,
                mindMap: payload.mindMap,
                engine: payload.engine
            )
            await store.saveAnalysis(analysis, artifactKind: .summary, logHistory: false)
        }
        
        return payload.summary
    }
    
    // MARK: - Transcript
    
    private func obtainTranscript(
        for item: DownloadItem,
        forceRetranscribe: Bool,
        session: UUID,
        store: StudyPersistenceActor,
        onProgress: TranscriptService.ProgressHandler?
    ) async throws -> (MediaTranscript, Bool) {
        if !forceRetranscribe, let cachedTranscript = await store.cachedTranscript(for: item) {
            onProgress?(TranscriptProgress(
                phase: .finishing,
                detail: "Using saved transcript — no download needed…"
            ))
            return (cachedTranscript, true)
        }
        
        if forceRetranscribe {
            logService.warning("Re-transcribing \(item.displayTitle) by explicit request")
        }
        
        if item.isStreamOnly, let kind = item.streamMediaKind {
            let transcript = try await transcriptService.transcribeFromSourceURL(
                item.url,
                mediaKind: kind,
                durationSeconds: item.durationSeconds,
                session: session,
                onProgress: onProgress
            )
            return (transcript, false)
        }
        
        if item.isResearchDocument, let bundleURL = item.paperBundleURL {
            onProgress?(TranscriptProgress(
                phase: .finishing,
                detail: "Extracting text from research paper…"
            ))
            let base = await PDFTextExtractor.extractTextWithOCR(bundleURL: bundleURL)
            let text = await PaperEnrichmentService.shared.appended(
                to: base, bundleURL: bundleURL, settings: LLMProviderSettings.load())
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MediaAIError.analysisFailed("Could not extract text from this paper.")
            }
            let transcript = MediaTranscript(
                text: text,
                createdAt: Date(),
                engine: .speechRecognizer,
                coveredSeconds: nil,
                sourceDurationSeconds: nil,
                coverageNote: "Extracted from PDF/HTML research document"
            )
            return (transcript, false)
        }
        
        guard let mediaURL = item.outputPath else {
            throw MediaAIError.analysisFailed("Missing media file.")
        }
        
        let transcript = try await transcriptService.transcribeMedia(at: mediaURL, session: session)
        return (transcript, false)
    }
    
    private func analyzeTranscript(
        _ transcript: String,
        title: String,
        forceRegenerate: Bool,
        session: UUID?,
        onProgress: TranscriptService.ProgressHandler? = nil,
        onPartial: (@Sendable (MediaAnalysisPayload) -> Void)? = nil
    ) async throws -> MediaAnalysisPayload {
        try await checkGenerationState(session: session)
        await Task.yield()

        // Bound the text given to NL tokenization, the research agent, and the
        // fallback ranker. The full transcript remains stored for display.
        let clampedTranscript = AnalysisText.clampedForAnalysis(transcript)
        if clampedTranscript.count < transcript.count {
            logService.warning(
                "Transcript clamped for analysis: \(transcript.count) → \(clampedTranscript.count) chars"
            )
        }
        let transcript = clampedTranscript

        let enableResearch = await MainActor.run { SettingsViewModel.isWebResearchEnabled }
        let researchContext = enableResearch
            ? await StudyResearchAgent.buildResearchContext(transcript: transcript, title: title)
            : nil
        try await checkGenerationState(session: session)

        // Prefer the configured BYOK cloud provider: ONE structured call instead
        // of dozens of sequential on-device calls (seconds, not minutes). The
        // provider picker is the choice — a cloud provider with a key generates
        // here; "On-Device" (or no key) falls through to the on-device path below.
        let providerSettings = LLMProviderSettings.load()
        let hasCloudKey = providerSettings.preset.keychainAccount.map { KeychainService.has($0) } ?? false
        if providerSettings.preset != .onDevice, hasCloudKey {
            do {
                onProgress?(TranscriptProgress(
                    phase: .analyzing,
                    detail: "Generating with \(providerSettings.preset.displayName)…"
                ))
                let payload = try await CloudAnalysisService.analyze(
                    transcript: transcript,
                    title: title,
                    settings: providerSettings,
                    researchContext: researchContext,
                    onPartial: onPartial
                )
                try await checkGenerationState(session: session)
                return payload
            } catch is CancellationError {
                throw MediaAIError.cancelled
            } catch {
                logService.warning(
                    "Cloud study generation failed; using on-device/fallback. \(error.localizedDescription)"
                )
                onProgress?(TranscriptProgress(
                    phase: .analyzing,
                    detail: "Cloud provider hit an error — finishing on-device…"
                ))
            }
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if FoundationModelBridge.isAvailable {
                guard let session else {
                    throw MediaAIError.analysisFailed("Study generation session required.")
                }
                do {
                    return try await FoundationModelBridge.analyze(
                        transcript: transcript,
                        title: title,
                        session: session,
                        options: FoundationModelAnalysisOptions(
                            forceRegenerate: forceRegenerate,
                            researchContext: researchContext,
                            enableWebResearchTool: enableResearch
                        ),
                        onProgress: { detail in
                            onProgress?(TranscriptProgress(phase: .analyzing, detail: detail))
                        }
                    )
                } catch is CancellationError {
                    throw MediaAIError.cancelled
                } catch {
                    logService.warning(
                        "Foundation Models study generation failed; using fallback. \(error.localizedDescription)"
                    )
                    onProgress?(TranscriptProgress(
                        phase: .analyzing,
                        detail: "On-device AI hit an error — finishing with fallback…"
                    ))
                }
            } else if let message = FoundationModelBridge.availabilityMessage {
                logService.warning("Foundation Models unavailable: \(message). Using fallback.")
            }
        }
        #endif
        
        let variationSeed: UInt64 = forceRegenerate
            ? UInt64(bitPattern: Int64(Date().timeIntervalSince1970))
            : 0
        
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            if let session {
                try await StudyGenerationCoordinator.shared.throwUnlessActive(session)
            }
            return FallbackAnalysisService.analyze(
                transcript: transcript,
                title: title,
                researchContext: researchContext,
                variationSeed: variationSeed
            )
        }.value
    }
    
    private static func isCompletePack(_ analysis: MediaAnalysis) -> Bool {
        StudyPersistenceActor.isCompleteStudyPack(analysis)
    }
    
    func isCompleteStudyPack(for downloadId: UUID) async -> Bool {
        guard let analysis = await persistence().loadAnalysis(for: downloadId) else { return false }
        return Self.isCompletePack(analysis)
    }
    
    func cancelActiveGeneration() {
        transcriptService.cancelActiveWork()
    }
    
    private func checkGenerationState(session: UUID?) async throws {
        guard let session else { return }
        try await StudyGenerationCoordinator.shared.throwUnlessActiveAndWait(session)
    }
}
