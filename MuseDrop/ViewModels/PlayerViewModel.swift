//
//  PlayerViewModel.swift
//  MuseDrop
//

import Foundation
import AVFoundation
import Combine

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var isPlaying: Bool = false
    /// True once the track has played to the end — the transport shows a replay
    /// icon and the next play restarts from the beginning.
    @Published var didReachEnd: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0
    /// Playback speed for the custom audio/podcast transport (0.75×–2×).
    @Published var playbackRate: Double = 1.0
    
    @Published var analysis: MediaAnalysis?
    @Published var selectedStudyTab: AIStudyTab = .canvas
    @Published var isGeneratingAI = false
    @Published var aiError: String?
    @Published var aiEngineDescription = ""
    
    @Published var flashcardIndex = 0
    @Published var showingFlashcardBack = false
    @Published var artifactHistory: [StudyArtifactHistoryItem] = []
    
    @Published var player: AVPlayer?
    @Published var isResolvingStream = false
    @Published var streamError: String?
    @Published var streamResolveDetail: String?
    /// When set, the video is played via the embedded YouTube player (full
    /// quality) instead of AVPlayer + yt-dlp (which caps at ~360p for streams).
    @Published var youtubeEmbedID: String?
    @Published var aiProgressDetail: String?
    @Published var isGenerationPaused = false
    @Published var isTranscriptionPhase = false
    @Published var showStoppedGenerationPrompt = false
    @Published var stoppedGenerationHasPartialData = false
    @Published var hasSavedTranscript = false
    @Published var savedTranscript: MediaTranscript?
    @Published var lastAnalysisEngine: AIEngineKind?

    // MARK: Translation overlay (on-demand, in-memory; never persisted)
    @Published var translatedAnalysis: MediaAnalysis?
    @Published var translatedTranscript: MediaTranscript?
    @Published var activeTranslationDisplayName: String?
    @Published var isTranslating = false
    /// Display name of the language currently being translated into (for status UI).
    @Published var translatingLanguageName: String?
    @Published var translationError: String?
    let translationCoordinator = StudyTranslationCoordinator()

    /// In-memory cache of already-translated packs, keyed by target language id
    /// (e.g. "fr"). Lets re-selecting a language — or returning to one after
    /// "Show original" — render instantly instead of re-running the whole pack
    /// through on-device translation. Cleared whenever the underlying content
    /// changes (new item or regenerated pack).
    private struct TranslatedPack {
        let analysis: MediaAnalysis?
        let transcript: MediaTranscript?
        let displayName: String
    }
    private var translationCache: [String: TranslatedPack] = [:]

    /// What the Study tabs should render — the translated copy when present.
    var displayedAnalysis: MediaAnalysis? { translatedAnalysis ?? analysis }
    /// What the Transcript tab should render, preferring any translated text.
    var displayedTranscript: MediaTranscript? {
        translatedAnalysis?.transcript ?? translatedTranscript ?? analysis?.transcript ?? savedTranscript
    }
    /// Detected language of the current source content (for the EN-input affordance).
    var transcriptSourceLanguage: Locale.Language? {
        let text = analysis?.transcript.text ?? savedTranscript?.text
        guard let text else { return nil }
        return StudyPackTranslator.detectLanguage(of: text)
    }
    var transcriptIsNonEnglish: Bool {
        guard let language = transcriptSourceLanguage else { return false }
        return !StudyPackTranslator.isEnglish(language)
    }

    private var timeObserver: Any?
    private var currentItemId: UUID?
    private var playbackItem: DownloadItem?
    private var generationTask: Task<Void, Never>?
    private var activeGenerationSession: UUID?
    private var streamLoadTask: Task<Void, Never>?
    private var streamLoadGeneration: UInt = 0
    
    private let mediaAI = MediaAIService.shared
    private let streamLibrary = StreamLibraryService.shared
    private var cancellables = Set<AnyCancellable>()
    
    func prepare(for item: DownloadItem) {
        currentItemId = item.id
        playbackItem = item
        aiEngineDescription = mediaAI.engineDescription
        aiError = nil
        streamError = nil
        streamResolveDetail = nil
        aiProgressDetail = nil
        flashcardIndex = 0
        showingFlashcardBack = false
        isGenerationPaused = false
        isTranscriptionPhase = false
        showStoppedGenerationPrompt = false
        stoppedGenerationHasPartialData = false
        
        analysis = nil
        savedTranscript = nil
        hasSavedTranscript = false
        lastAnalysisEngine = nil
        artifactHistory = []
        clearTranslation()
        translationCache.removeAll()

        Task {
            await loadStudyState(for: item)
        }
    }
    
    private func loadStudyState(for item: DownloadItem) async {
        guard currentItemId == item.id else { return }
        
        let persistence = await studyPersistence()
        async let cachedAnalysis = mediaAI.loadCachedAnalysis(for: item)
        async let transcript = mediaAI.loadSavedTranscript(for: item)
        async let history = persistence.artifactHistory(for: item.id)
        
        let analysis = await cachedAnalysis
        let saved = await transcript
        let items = await history
        
        guard currentItemId == item.id else { return }
        self.analysis = analysis
        self.savedTranscript = saved
        self.hasSavedTranscript = saved != nil
        self.lastAnalysisEngine = analysis?.engine
        self.artifactHistory = items
    }
    
    private func studyPersistence() async -> StudyPersistenceActor {
        await MainActor.run { DataStore.shared.studyPersistence }
    }
    
    func loadMedia(_ item: DownloadItem) {
        if item.isResearchDocument { return }
        if item.isStreamOnly {
            // YouTube streams play via the embedded YouTube player for full
            // quality — yt-dlp can only resolve ~360p as a single AVPlayer URL.
            if let ytID = MediaSourceIdentity.youtubeVideoID(from: item.url) {
                youtubeEmbedID = ytID
                return
            }
            startStreamLoad(for: item, forceRefresh: false)
            return
        }
        
        guard let url = item.outputPath else { return }
        setupPlayer(with: url, durationHint: nil, streamGeneration: nil)
    }
    
    private func startStreamLoad(for item: DownloadItem, forceRefresh: Bool) {
        streamLoadTask?.cancel()
        let generation = streamLoadGeneration &+ 1
        streamLoadGeneration = generation
        streamLoadTask = Task { [weak self] in
            await self?.loadStreamMedia(item, forceRefresh: forceRefresh, generation: generation)
        }
    }
    
    private func loadStreamMedia(
        _ item: DownloadItem,
        forceRefresh: Bool = false,
        generation: UInt
    ) async {
        guard !Task.isCancelled, generation == streamLoadGeneration else { return }
        
        isResolvingStream = true
        streamError = nil
        streamResolveDetail = "Starting stream resolution…"
        cleanupObservers()
        player = nil
        
        do {
            let playable = try await streamLibrary.playbackItem(
                for: item,
                forceRefresh: forceRefresh
            ) { [weak self] detail in
                Task { @MainActor in
                    guard let self, generation == self.streamLoadGeneration else { return }
                    self.streamResolveDetail = detail
                }
            }
            guard !Task.isCancelled, generation == streamLoadGeneration else { return }
            
            playbackItem = playable
            streamResolveDetail = nil
            guard let streamURL = playable.streamURL else {
                streamError = "Stream URL unavailable. Try refreshing the stream."
                return
            }
            setupPlayer(with: streamURL, durationHint: playable.durationSeconds, streamGeneration: generation)
        } catch {
            guard generation == streamLoadGeneration else { return }
            if !Task.isCancelled {
                streamError = error.localizedDescription
            }
            streamResolveDetail = nil
        }
        
        guard generation == streamLoadGeneration else { return }
        isResolvingStream = false
    }
    
    func refreshStreamIfNeeded() async {
        guard var item = playbackItem, item.isStreamOnly else { return }
        streamLibrary.invalidatePersistedPlayback(for: item)
        item.streamURL = nil
        item.streamExpiresAt = nil
        playbackItem = item
        startStreamLoad(for: item, forceRefresh: true)
    }
    
    // MARK: - Transport (custom audio/podcast controls)

    func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            // At the end of the track, AVPlayer won't advance on play() — restart
            // from the beginning so the play button doubles as a replay.
            if didReachEnd || (duration > 0 && currentTime >= duration - 0.25) {
                player.seek(to: .zero)
                currentTime = 0
                didReachEnd = false
            }
            player.play()
            player.rate = Float(playbackRate)
        }
    }

    /// Restart the track from the beginning and play.
    func restart() {
        guard let player else { return }
        player.seek(to: .zero)
        currentTime = 0
        didReachEnd = false
        player.play()
        player.rate = Float(playbackRate)
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let target = duration > 0 ? min(max(0, time), duration) : max(0, time)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        // Seeking back from the end clears the finished state.
        if target < duration - 0.25 { didReachEnd = false }
    }

    /// Relative skip (e.g. −15 / +15 seconds).
    func skip(_ seconds: Double) { seek(to: currentTime + seconds) }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        player?.defaultRate = Float(rate)
        if player?.timeControlStatus == .playing { player?.rate = Float(rate) }
    }

    private func setupPlayer(with url: URL, durationHint: Double?, streamGeneration: UInt?) {
        cleanupObservers()
        didReachEnd = false

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 15
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.volume = volume
        player = newPlayer
        newPlayer.play()
        
        if let durationHint, durationHint > 0 {
            duration = durationHint
        }
        
        Task {
            if let asset = newPlayer.currentItem?.asset {
                let loadedDuration = try? await asset.load(.duration)
                if let loadedDuration, CMTimeGetSeconds(loadedDuration) > 0 {
                    duration = CMTimeGetSeconds(loadedDuration)
                }
            }
        }
        
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.isPlaying = self.player?.timeControlStatus == .playing
        }
        
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isPlaying = false
                self.didReachEnd = true
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshStreamIfNeeded() }
            }
            .store(in: &cancellables)
        
        if let streamGeneration, streamGeneration != streamLoadGeneration {
            player = nil
        }
    }
    
    func generateStudyMaterials(for item: DownloadItem, forceRegenerate: Bool = false) {
        generationTask?.cancel()
        generationTask = Task {
            let hasTranscript = await mediaAI.hasSavedTranscript(for: item)
            let shouldReplaceExisting = forceRegenerate || hasTranscript
            await performStudyGeneration(for: item, forceRegenerate: shouldReplaceExisting)
        }
    }
    
    func pauseGeneration() {
        guard isGeneratingAI, !isGenerationPaused else { return }
        isGenerationPaused = true
        aiProgressDetail = "Paused — tap Resume to continue"
        Task { await StudyGenerationCoordinator.shared.pause() }
    }
    
    func resumeGeneration() {
        guard isGeneratingAI, isGenerationPaused else { return }
        isGenerationPaused = false
        aiProgressDetail = "Resuming…"
        Task { await StudyGenerationCoordinator.shared.resume() }
    }
    
    func stopGeneration() {
        if let session = activeGenerationSession {
            Task { await StudyGenerationCoordinator.shared.cancel(session: session) }
        }
        generationTask?.cancel()
        mediaAI.cancelActiveGeneration()
        isGenerationPaused = false
    }
    
    func dismissStoppedGenerationPrompt() {
        showStoppedGenerationPrompt = false
        stoppedGenerationHasPartialData = false
    }
    
    func deletePartialStudyData(for item: DownloadItem) {
        Task {
            await studyPersistence().deleteStudySession(for: item.id)
            guard currentItemId == item.id else { return }
            analysis = nil
            savedTranscript = nil
            hasSavedTranscript = false
            lastAnalysisEngine = nil
            artifactHistory = []
            aiError = nil
            showStoppedGenerationPrompt = false
            stoppedGenerationHasPartialData = false
            LibraryManager.shared.reloadDownloads()
        }
    }
    
    private func performStudyGeneration(for item: DownloadItem, forceRegenerate: Bool) async {
        let session = UUID()
        activeGenerationSession = session
        
        isGeneratingAI = true
        aiError = nil
        aiProgressDetail = forceRegenerate ? "Re-analyzing study pack…" : "Starting…"
        showStoppedGenerationPrompt = false
        stoppedGenerationHasPartialData = false
        isGenerationPaused = false
        isTranscriptionPhase = false
        
        if forceRegenerate {
            analysis = nil
        }
        
        await Task.yield()
        await StudyGenerationCoordinator.shared.begin(session: session)
        
        let shouldResumePlayback = player?.timeControlStatus == .playing
        player?.pause()
        
        do {
            try Task.checkCancellation()
            let result = try await mediaAI.generateAnalysis(
                for: item,
                forceRegenerate: forceRegenerate,
                session: session,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self,
                              self.activeGenerationSession == session,
                              !self.isGenerationPaused else { return }
                        self.isTranscriptionPhase = [
                            .fetchingCaptions,
                            .extractingAudio,
                            .transcribing
                        ].contains(progress.phase)
                        self.aiProgressDetail = progress.detail
                    }
                },
                onPartial: { [weak self] partial in
                    // Fill the study tabs progressively as each artifact lands.
                    Task { @MainActor in
                        guard let self,
                              self.activeGenerationSession == session,
                              !self.isGenerationPaused else { return }
                        self.analysis = partial
                        self.lastAnalysisEngine = partial.engine
                    }
                }
            )
            guard activeGenerationSession == session else { return }
            
            analysis = result
            // Pack content changed — any cached translations are now stale.
            translationCache.removeAll()
            clearTranslation()
            lastAnalysisEngine = result.engine
            savedTranscript = result.transcript
            hasSavedTranscript = true
            LibraryManager.shared.markSummaryExists(for: item.id)
            artifactHistory = await studyPersistence().artifactHistory(for: item.id)
            flashcardIndex = 0
            showingFlashcardBack = false
        } catch is CancellationError {
            guard activeGenerationSession == session else { return }
            await handleGenerationStopped(for: item)
        } catch {
            guard activeGenerationSession == session else { return }
            if Task.isCancelled {
                await handleGenerationStopped(for: item)
            } else {
                aiError = error.localizedDescription
            }
        }
        
        finishGenerationIfCurrent(session: session, shouldResumePlayback: shouldResumePlayback)
    }
    
    private func finishGenerationIfCurrent(session: UUID, shouldResumePlayback: Bool) {
        guard activeGenerationSession == session else { return }
        isGeneratingAI = false
        isGenerationPaused = false
        isTranscriptionPhase = false
        aiProgressDetail = nil
        generationTask = nil
        if shouldResumePlayback, !Task.isCancelled {
            player?.play()
        }
    }
    
    private func handleGenerationStopped(for item: DownloadItem) async {
        let persistence = await studyPersistence()
        let hasPartial = await persistence.hasIncompleteStudySession(for: item.id)
        guard currentItemId == item.id else { return }
        
        stoppedGenerationHasPartialData = hasPartial
        showStoppedGenerationPrompt = true
        
        if hasPartial {
            analysis = nil
        } else if let cached = await mediaAI.loadCachedAnalysis(for: item) {
            analysis = cached
            aiError = nil
        } else {
            analysis = nil
            aiError = nil
        }
    }
    
    func nextFlashcard() {
        guard let cards = displayedAnalysis?.flashcards, !cards.isEmpty else { return }
        flashcardIndex = (flashcardIndex + 1) % cards.count
        showingFlashcardBack = false
    }

    func previousFlashcard() {
        guard let cards = displayedAnalysis?.flashcards, !cards.isEmpty else { return }
        flashcardIndex = (flashcardIndex - 1 + cards.count) % cards.count
        showingFlashcardBack = false
    }

    // MARK: - Translation

    func clearTranslation() {
        translatedAnalysis = nil
        translatedTranscript = nil
        activeTranslationDisplayName = nil
        translationError = nil
    }

    /// Output direction: translate the whole displayed pack (or bare transcript)
    /// into `option` for reading. Overlay only — nothing is persisted.
    func translatePack(to option: TranslationLanguageOption) async {
        guard analysis != nil || savedTranscript != nil else { return }
        let itemId = currentItemId
        translationError = nil

        // Instant if we already built this language for the current pack.
        if let cached = translationCache[option.id] {
            translatedAnalysis = cached.analysis
            translatedTranscript = cached.transcript
            activeTranslationDisplayName = cached.displayName
            flashcardIndex = 0
            showingFlashcardBack = false
            return
        }

        isTranslating = true
        translatingLanguageName = option.displayName
        defer {
            isTranslating = false
            translatingLanguageName = nil
        }

        let sourceText = analysis?.transcript.text ?? savedTranscript?.text ?? ""
        let source = StudyPackTranslator.detectLanguage(of: sourceText)
        let target = option.language

        let status = await translationCoordinator.availability(from: source, to: target)
        guard currentItemId == itemId else { return }
        if status == .unsupported {
            translationError = StudyTranslationCoordinator.BridgeError
                .unsupportedLanguage(option.displayName).localizedDescription
            return
        }

        do {
            if let analysis {
                let reqs = StudyPackTranslator.requests(for: analysis, includeTranscript: true)
                let tr = try await translationCoordinator.translate(reqs, from: source, to: target)
                guard currentItemId == itemId else { return }
                translatedAnalysis = StudyPackTranslator.apply(tr, to: analysis, includeTranscript: true)
                translatedTranscript = nil
            } else if let saved = savedTranscript {
                let reqs = StudyPackTranslator.requests(for: saved)
                let tr = try await translationCoordinator.translate(reqs, from: source, to: target)
                guard currentItemId == itemId else { return }
                translatedTranscript = StudyPackTranslator.applyTranscript(tr, to: saved)
                translatedAnalysis = nil
            }
            activeTranslationDisplayName = option.displayName
            translationCache[option.id] = TranslatedPack(
                analysis: translatedAnalysis,
                transcript: translatedTranscript,
                displayName: option.displayName
            )
            flashcardIndex = 0
            showingFlashcardBack = false
        } catch {
            guard currentItemId == itemId else { return }
            translationError = error.localizedDescription
        }
    }

    /// Input direction: translate a non-English transcript to English, persist it
    /// as the working transcript, then regenerate so the pack is built in English.
    func translateTranscriptToEnglishAndRegenerate(for item: DownloadItem) async {
        guard let transcript = analysis?.transcript ?? savedTranscript else { return }
        let itemId = currentItemId
        translationError = nil
        isTranslating = true

        let source = StudyPackTranslator.detectLanguage(of: transcript.text)
        let english = Locale.Language(identifier: "en")
        do {
            let reqs = StudyPackTranslator.requests(for: transcript)
            let tr = try await translationCoordinator.translate(reqs, from: source, to: english)
            guard currentItemId == itemId else { isTranslating = false; return }
            let englishTranscript = StudyPackTranslator.applyTranscript(tr, to: transcript)

            // Replace the cached transcript so generation reuses it (no re-download).
            let partial = MediaAnalysis(
                downloadId: item.id,
                mediaTitle: item.displayTitle,
                transcript: englishTranscript,
                summary: SummaryResult(),
                engine: .naturalLanguageFallback
            )
            await studyPersistence().saveAnalysis(partial, artifactKind: .transcript)
            guard currentItemId == itemId else { isTranslating = false; return }

            savedTranscript = englishTranscript
            hasSavedTranscript = true
            analysis = nil
            clearTranslation()
            isTranslating = false
            generateStudyMaterials(for: item, forceRegenerate: true)
        } catch {
            isTranslating = false
            guard currentItemId == itemId else { return }
            translationError = error.localizedDescription
        }
    }
    
    func toggleFlashcardSide() {
        showingFlashcardBack.toggle()
    }
    
    func cleanup() {
        streamLoadGeneration &+= 1
        streamLoadTask?.cancel()
        streamLoadTask = nil
        
        if let session = activeGenerationSession {
            Task { await StudyGenerationCoordinator.shared.cancel(session: session) }
        }
        activeGenerationSession = nil
        generationTask?.cancel()
        generationTask = nil
        mediaAI.cancelActiveGeneration()
        stopPlayback()
        currentItemId = nil
        playbackItem = nil
        isResolvingStream = false
        streamError = nil
        streamResolveDetail = nil
        aiProgressDetail = nil
        isGeneratingAI = false
        isGenerationPaused = false
        isTranscriptionPhase = false
    }
    
    private func stopPlayback() {
        cleanupObservers()
        if let player {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        player = nil
        // Drop the YouTube embed too: clearing this removes YouTubeEmbedView from
        // the tree, which triggers its dismantleNSView and stops the WKWebView.
        // Otherwise a YouTube video keeps playing audio after the window closes.
        youtubeEmbedID = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        didReachEnd = false
    }
    
    private func cleanupObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        cancellables.removeAll()
    }
}
