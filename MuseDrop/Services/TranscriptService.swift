//
//  TranscriptService.swift
//  MuseDrop
//
//  Transcription strategy (by speed):
//  1. YouTube/platform captions via yt-dlp --skip-download (no ffmpeg, seconds)
//  2. Sampled audio sections via yt-dlp --download-sections + ffmpeg (long videos)
//  3. SpeechAnalyzer on small local clips only
//

import Foundation
import Speech
import AVFoundation

enum TranscriptionEngine: String, Codable {
    case speechAnalyzer
    case speechRecognizer
    case platformCaptions
}

enum TranscriptProgressPhase: String {
    case fetchingCaptions
    case extractingAudio
    case transcribing
    case analyzing
    case finishing
}

struct TranscriptProgress {
    var phase: TranscriptProgressPhase
    var detail: String
}

enum TranscriptError: LocalizedError {
    case ffmpegNotFound
    case ytDlpNotFound
    case audioExtractionFailed(String)
    case speechRecognitionUnavailable
    case speechRecognitionDenied(String? = nil)
    case modelAssetsUnavailable
    case emptyTranscript
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Please ensure ffmpeg is installed."
        case .ytDlpNotFound:
            return "yt-dlp not found."
        case .audioExtractionFailed(let message):
            return "Failed to extract audio: \(message)"
        case .speechRecognitionUnavailable:
            return "Speech transcription is not available for this language on this device."
        case .speechRecognitionDenied(let reason):
            return reason ?? "Speech recognition permission is required. Enable it in System Settings → Privacy & Security → Speech Recognition."
        case .modelAssetsUnavailable:
            return "The on-device speech model is still downloading. Connect to the internet and try again."
        case .emptyTranscript:
            return "No speech was detected in this file."
        }
    }
}

final class TranscriptService {
    static let shared = TranscriptService()

    /// Ceiling for ffmpeg audio conversion (generous: long lectures convert
    /// faster than realtime, but we never want to hang forever).
    private static let audioConvertTimeout: TimeInterval = 900

    private let logService = LogService.shared
    private let preferredLocale = Locale(identifier: "en-US")
    private let speechCancelLock = NSLock()
    private var speechCancelHandler: (() -> Void)?

    // A transcription job runs several subprocesses in sequence. ProcessRunner is
    // documented as one-instance-per-operation, so we create a fresh runner per
    // process and track the most recent one here so cancelActiveWork() can stop it.
    private let runnerLock = NSLock()
    private var activeRunner: ProcessRunner?

    private func makeActiveRunner() -> ProcessRunner {
        let runner = ProcessRunner()
        runnerLock.lock()
        activeRunner = runner
        runnerLock.unlock()
        return runner
    }
    
    /// Below this duration, download the full audio for speech recognition.
    private let fullAudioThresholdSeconds: Double = 20 * 60
    /// Per-section download cap when captions are unavailable.
    private let sectionExtractTimeout: TimeInterval = 120
    /// Single quick sample when captions fail on long videos.
    private let quickFallbackSeconds: Double = 12 * 60
    
    private init() {}
    
    func cancelActiveWork() {
        runnerLock.lock()
        let runner = activeRunner
        runnerLock.unlock()
        runner?.cancel()
        speechCancelLock.lock()
        let handler = speechCancelHandler
        speechCancelHandler = nil
        speechCancelLock.unlock()
        handler?()
    }
    
    private func registerSpeechCancel(_ handler: @escaping () -> Void) {
        speechCancelLock.lock()
        speechCancelHandler = handler
        speechCancelLock.unlock()
    }
    
    private func clearSpeechCancel() {
        speechCancelLock.lock()
        speechCancelHandler = nil
        speechCancelLock.unlock()
    }
    
    private final class TranscriptResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        
        func resumeOnce(_ action: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !resumed else { return }
            resumed = true
            action()
        }
    }
    
    private func checkGenerationState(session: UUID?) async throws {
        guard let session else { return }
        try await StudyGenerationCoordinator.shared.throwUnlessActiveAndWait(session)
    }
    
    var activeEngineDescription: String {
        if #available(macOS 26.0, *) {
            return "Captions or SpeechAnalyzer"
        }
        return "Captions or SFSpeechRecognizer"
    }
    
    typealias ProgressHandler = @Sendable (TranscriptProgress) -> Void
    
    func transcribeMedia(at mediaURL: URL, session: UUID? = nil) async throws -> MediaTranscript {
        logService.info("Starting transcription for \(mediaURL.lastPathComponent)")
        try await checkGenerationState(session: session)
        try await ensureSpeechAuthorization()
        
        let audioURL: URL
        let shouldDeleteAudio: Bool
        
        if isDirectAudioFile(mediaURL) {
            audioURL = mediaURL
            shouldDeleteAudio = false
        } else {
            audioURL = try await extractAudio(from: mediaURL)
            shouldDeleteAudio = true
        }
        
        defer {
            if shouldDeleteAudio {
                try? FileUtils.deleteFile(at: audioURL)
            }
        }
        
        try await checkGenerationState(session: session)
        let result = try await runSpeechRecognition(on: audioURL)
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptError.emptyTranscript }
        
        let sourceDuration = await mediaDurationSeconds(at: mediaURL)
        return MediaTranscript(
            text: trimmed,
            engine: result.engine,
            coveredSeconds: sourceDuration,
            sourceDurationSeconds: sourceDuration,
            coverageNote: "Full local file"
        )
    }
    
    /// Stream & Study: captions first, then sampled audio — never full-hour WAV download.
    func transcribeFromSourceURL(
        _ sourceURL: String,
        mediaKind: StreamMediaKind,
        durationSeconds: Double? = nil,
        session: UUID? = nil,
        onProgress: ProgressHandler? = nil
    ) async throws -> MediaTranscript {
        try await checkGenerationState(session: session)
        onProgress?(TranscriptProgress(phase: .fetchingCaptions, detail: "Checking for platform captions…"))
        
        if let captions = try await fetchPlatformCaptions(sourceURL: sourceURL) {
            logService.info("Using platform captions (\(captions.text.count) chars)")
            return captions
        }
        
        try await checkGenerationState(session: session)
        logService.warning("No platform captions found — falling back to audio sampling")
        try await ensureSpeechAuthorization()
        
        let duration: Double
        if let durationSeconds, durationSeconds > 0 {
            duration = durationSeconds
        } else {
            let meta = try? await StreamResolverService.shared.fetchMetadata(for: sourceURL)
            duration = meta?.durationSeconds ?? 0
        }
        let sections = samplingSections(totalDuration: duration)
        
        onProgress?(TranscriptProgress(
            phase: .extractingAudio,
            detail: "Downloading first \(formatDuration(sections[0].duration)) of audio (captions unavailable)…"
        ))
        
        var combined = ""
        var covered: Double = 0
        
        for (index, section) in sections.enumerated() {
            try await checkGenerationState(session: session)
            onProgress?(TranscriptProgress(
                phase: .transcribing,
                detail: "Transcribing section \(index + 1) of \(sections.count)…"
            ))
            
            let audioURL = try await extractAudioSection(sourceURL: sourceURL, section: section)
            defer { try? FileUtils.deleteFile(at: audioURL) }
            
            try await checkGenerationState(session: session)
            let result = try await runSpeechRecognition(on: audioURL)
            if !result.text.isEmpty {
                combined += (combined.isEmpty ? "" : "\n\n") + result.text
            }
            covered += section.duration
        }
        
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptError.emptyTranscript }
        
        let coverageNote: String
        if duration <= 0 {
            // Duration unknown: we used a fabricated single segment, so don't
            // claim a specific covered amount or "full audio".
            coverageNote = "Transcribed first segment (duration unknown)"
        } else if sections.count == 1 && duration > fullAudioThresholdSeconds {
            coverageNote = "Sampled first \(formatDuration(sections[0].duration)) (captions unavailable)"
        } else if sections.count == 1 {
            coverageNote = "Full audio via SpeechAnalyzer"
        } else {
            coverageNote = "Sampled \(sections.count) sections (~\(formatDuration(covered)) of \(formatDuration(duration)))"
        }
        
        onProgress?(TranscriptProgress(phase: .finishing, detail: "Preparing study materials…"))
        
        return MediaTranscript(
            text: trimmed,
            engine: .speechAnalyzer,
            coveredSeconds: duration > 0 ? covered : nil,
            sourceDurationSeconds: duration > 0 ? duration : nil,
            coverageNote: coverageNote
        )
    }
    
    // MARK: - Captions (fast path, no ffmpeg)
    
    private func fetchPlatformCaptions(sourceURL: String) async throws -> MediaTranscript? {
        guard let ytDlpPath = PathUtils.getYtDlpPath() else { return nil }
        
        // Fast path: read caption URLs from metadata JSON and download directly.
        if let transcript = try await fetchCaptionsFromMetadata(sourceURL: sourceURL, ytDlpPath: ytDlpPath) {
            logService.info("Loaded platform captions from metadata (\(transcript.text.count) chars)")
            return transcript
        }
        
        // Fallback: write subtitle files via yt-dlp.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kekasatori-subs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        
        let outputTemplate = workDir.appendingPathComponent("subs.%(ext)s").path
        
        do {
            let (_, stderr, code) = try await YTDlpProcessGate.shared.run {
                try await makeActiveRunner().run(
                    executable: ytDlpPath,
                    arguments: [
                        "--skip-download",
                        "--write-subs",
                        "--write-auto-subs",
                        "--sub-langs", "en.*,en,-live_chat",
                        "--sub-format", "vtt/best",
                        "-o", outputTemplate,
                        "--no-playlist",
                        "--no-warnings",
                        sourceURL
                    ],
                    workingDirectory: workDir,
                    timeout: 45
                )
            }
            guard code == 0 else {
                logService.debug("Subtitle file write failed: \(stderr.prefix(300))")
                return nil
            }
        } catch {
            logService.debug("Subtitle fetch error: \(error.localizedDescription)")
            return nil
        }
        
        guard let subFile = findSubtitleFile(in: workDir),
              let contents = readSubtitleText(subFile) else {
            return nil
        }
        
        let plain = SubtitleParser.plainText(from: contents)
        guard plain.count > 80 else { return nil }
        
        return MediaTranscript(
            text: plain,
            engine: .platformCaptions,
            coverageNote: "Platform captions (full video)"
        )
    }
    
    private func fetchCaptionsFromMetadata(sourceURL: String, ytDlpPath: URL) async throws -> MediaTranscript? {
        let (stdout, _, code) = try await YTDlpProcessGate.shared.run {
            try await makeActiveRunner().run(
                executable: ytDlpPath,
                arguments: ["-j", "--skip-download", "--no-playlist", "--no-warnings", sourceURL],
                timeout: 45
            )
        }
        guard code == 0,
              let data = stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let captionURL = pickCaptionURL(from: json) else {
            return nil
        }
        
        var request = URLRequest(url: captionURL)
        request.timeoutInterval = 30
        let (captionData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        
        let raw = decodeSubtitleData(captionData) ?? ""
        let plain = SubtitleParser.plainText(from: raw)
        guard plain.count > 80 else { return nil }
        
        let duration = (json["duration"] as? Double) ?? (json["duration"] as? Int).map(Double.init)
        
        return MediaTranscript(
            text: plain,
            engine: .platformCaptions,
            coveredSeconds: duration,
            sourceDurationSeconds: duration,
            coverageNote: "Platform captions (full video)"
        )
    }
    
    private func pickCaptionURL(from json: [String: Any]) -> URL? {
        let buckets = ["subtitles", "automatic_captions"]
        let preferredLangs = ["en-orig", "en", "en-US", "en-GB"]
        let preferredExts = ["vtt", "srt", "json3", "srv3", "ttml"]
        
        for bucket in buckets {
            guard let languages = json[bucket] as? [String: Any] else { continue }
            
            var langKeys = preferredLangs.filter { languages[$0] != nil }
            // Only fall back to other English-family tracks (e.g. en-CA, en-IN).
            // A non-English track would be fed to an en-US study pack, so skip it.
            let englishFallback = languages.keys
                .filter { $0.lowercased().hasPrefix("en") && !langKeys.contains($0) }
                .sorted()
            langKeys.append(contentsOf: englishFallback)
            
            for lang in langKeys {
                guard let tracks = languages[lang] as? [[String: Any]] else { continue }
                for ext in preferredExts {
                    if let track = tracks.first(where: { ($0["ext"] as? String) == ext }),
                       let urlString = track["url"] as? String,
                       let url = URL(string: urlString) {
                        return url
                    }
                }
            }
        }
        return nil
    }
    
    /// Reads a subtitle file with encoding detection. Some platforms emit
    /// UTF-16/Latin-1 rather than UTF-8, so try detection first, then fall back.
    private func readSubtitleText(_ url: URL) -> String? {
        var usedEncoding = String.Encoding.utf8
        if let detected = try? String(contentsOf: url, usedEncoding: &usedEncoding) {
            return detected
        }
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }

    /// Decodes downloaded subtitle bytes with the same encoding fallback chain.
    private func decodeSubtitleData(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private func findSubtitleFile(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return nil }
        
        for case let file as URL in enumerator {
            let ext = file.pathExtension.lowercased()
            if ["vtt", "srt", "json3"].contains(ext) {
                return file
            }
        }
        return nil
    }
    
    // MARK: - Section sampling
    
    private struct AudioSection {
        let start: Double
        let end: Double
        var duration: Double { end - start }
        var rangeLabel: String {
            "\(Self.formatTimestamp(start))-\(Self.formatTimestamp(end))"
        }
        
        private static func formatTimestamp(_ seconds: Double) -> String {
            let total = Int(seconds)
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%d:%02d", m, s)
        }
    }
    
    private func samplingSections(totalDuration: Double) -> [AudioSection] {
        guard totalDuration > fullAudioThresholdSeconds else {
            return [AudioSection(start: 0, end: max(totalDuration, 60))]
        }
        
        // One opening segment only — avoids 5 parallel-heavy extractions on long videos.
        let sampleEnd = min(quickFallbackSeconds, totalDuration)
        logService.info("Captions unavailable — sampling first \(Int(sampleEnd / 60)) min for speech recognition")
        return [AudioSection(start: 0, end: sampleEnd)]
    }
    
    private func extractAudioSection(sourceURL: String, section: AudioSection) async throws -> URL {
        guard let ytDlpPath = PathUtils.getYtDlpPath() else {
            throw TranscriptError.ytDlpNotFound
        }
        guard let ffmpegPath = PathUtils.getFfmpegPath() else {
            throw TranscriptError.ffmpegNotFound
        }
        
        let outputURL = try FileUtils.createTempFile(extension: "wav")
        let args = [
            "-f", "ba/b",
            "--download-sections", "*\(section.rangeLabel)",
            "-x", "--audio-format", "wav",
            "--ffmpeg-location", ffmpegPath.path,
            "-o", outputURL.deletingPathExtension().path,
            "--no-playlist",
            "--no-warnings",
            sourceURL
        ]
        
        let (stdout, stderr, exitCode) = try await YTDlpProcessGate.shared.run {
            try await makeActiveRunner().run(
                executable: ytDlpPath,
                arguments: args,
                timeout: sectionExtractTimeout
            )
        }
        
        guard exitCode == 0 else {
            throw TranscriptError.audioExtractionFailed(stderr.isEmpty ? stdout : stderr)
        }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }
        
        let directory = outputURL.deletingLastPathComponent()
        let stem = outputURL.deletingPathExtension().lastPathComponent
        if let match = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent.hasPrefix(stem) && ["wav", "m4a", "opus"].contains($0.pathExtension.lowercased()) }) {
            return try await convertToWAV(match)
        }
        
        throw TranscriptError.audioExtractionFailed("No audio file for section \(section.rangeLabel)")
    }
    
    private func convertToWAV(_ input: URL) async throws -> URL {
        guard let ffmpegPath = PathUtils.getFfmpegPath() else {
            throw TranscriptError.ffmpegNotFound
        }
        let outputURL = try FileUtils.createTempFile(extension: "wav")
        let (_, stderr, code) = try await makeActiveRunner().run(
            executable: ffmpegPath,
            arguments: ["-y", "-i", input.path, "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1", outputURL.path],
            timeout: Self.audioConvertTimeout
        )
        guard code == 0 else {
            throw TranscriptError.audioExtractionFailed(stderr)
        }
        return outputURL
    }
    
    // MARK: - Speech recognition
    
    private func runSpeechRecognition(on audioURL: URL) async throws -> (text: String, engine: TranscriptionEngine) {
        if #available(macOS 26.0, *) {
            do {
                return try await transcribeWithSpeechAnalyzer(audioURL: audioURL)
            } catch {
                logService.warning("SpeechAnalyzer failed, falling back: \(error.localizedDescription)")
                return try await transcribeWithSpeechRecognizer(audioURL: audioURL)
            }
        }
        return try await transcribeWithSpeechRecognizer(audioURL: audioURL)
    }
    
    @available(macOS 26.0, *)
    private func transcribeWithSpeechAnalyzer(audioURL: URL) async throws -> (text: String, engine: TranscriptionEngine) {
        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: preferredLocale)
        let fallbackLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        guard let locale = supportedLocale ?? fallbackLocale else {
            throw TranscriptError.speechRecognitionUnavailable
        }
        
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        
        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installationRequest.downloadAndInstall()
        }
        
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        registerSpeechCancel {
            Task {
                await analyzer.cancelAndFinishNow()
            }
        }
        defer { clearSpeechCancel() }
        
        async let transcriptFuture: String = {
            var combined = AttributedString("")
            for try await result in transcriber.results {
                combined += result.text
            }
            return String(combined.characters)
        }()
        
        let audioFile = try AVAudioFile(forReading: audioURL)
        
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        
        return (try await transcriptFuture, .speechAnalyzer)
    }
    
    private func transcribeWithSpeechRecognizer(audioURL: URL) async throws -> (text: String, engine: TranscriptionEngine) {
        let recognizer = SFSpeechRecognizer(locale: preferredLocale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptError.speechRecognitionUnavailable
        }
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        
        let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let resumeGuard = TranscriptResumeGuard()
            var recognitionTask: SFSpeechRecognitionTask?
            
            registerSpeechCancel {
                resumeGuard.resumeOnce {
                    recognitionTask?.cancel()
                    continuation.resume(throwing: CancellationError())
                }
            }
            
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    resumeGuard.resumeOnce {
                        self.clearSpeechCancel()
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                resumeGuard.resumeOnce {
                    self.clearSpeechCancel()
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
        
        return (text, .speechRecognizer)
    }
    
    // MARK: - Local file audio prep
    
    private func extractAudio(from mediaURL: URL) async throws -> URL {
        guard let ffmpegPath = PathUtils.getFfmpegPath(),
              FileManager.default.fileExists(atPath: ffmpegPath.path) else {
            throw TranscriptError.ffmpegNotFound
        }
        
        let outputURL = try FileUtils.createTempFile(extension: "wav")
        let (_, stderr, exitCode) = try await makeActiveRunner().run(
            executable: ffmpegPath,
            arguments: [
                "-y", "-i", mediaURL.path,
                "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
                outputURL.path
            ],
            timeout: Self.audioConvertTimeout
        )
        
        guard exitCode == 0 else {
            throw TranscriptError.audioExtractionFailed(stderr)
        }
        return outputURL
    }
    
    private func isDirectAudioFile(_ url: URL) -> Bool {
        ["wav", "m4a", "aac", "caf"].contains(url.pathExtension.lowercased())
    }
    
    private func ensureSpeechAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized: return
        case .restricted:
            throw TranscriptError.speechRecognitionDenied("Speech Recognition is restricted on this device.")
        case .denied, .notDetermined:
            throw TranscriptError.speechRecognitionDenied()
        @unknown default:
            throw TranscriptError.speechRecognitionDenied()
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m) min"
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
    
    private func mediaDurationSeconds(at url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
