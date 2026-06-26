//
//  PodcastSheet.swift
//  Kekasatori
//
//  Generate a two-host audio "podcast" from a selected page range of the paper,
//  via Gemini (BYOK). Preview it, then add it to the Library as an audio item
//  (where it plays in the normal player and can have a study pack generated).
//

import SwiftUI
import AVFoundation

struct PodcastSheet: View {
    let paperTitle: String
    let pageCount: Int
    /// Returns cleaned text for an inclusive 1-based page range.
    let textForPages: (Int, Int) -> String

    @Environment(\.dismiss) private var dismiss

    @State private var fromPage: Int
    @State private var toPage: Int
    @State private var apiKeyInput = ""
    @State private var hasKey = GeminiPodcastService.shared.hasKey
    @State private var isWorking = false
    @State private var detail = ""
    @State private var errorText: String?
    @State private var resultURL: URL?
    @State private var resultDuration: Double = 0
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    init(paperTitle: String, pageCount: Int, initialPage: Int, textForPages: @escaping (Int, Int) -> String) {
        self.paperTitle = paperTitle
        self.pageCount = max(1, pageCount)
        self.textForPages = textForPages
        let start = min(max(1, initialPage), self.pageCount)
        _fromPage = State(initialValue: start)
        _toPage = State(initialValue: min(start + 2, self.pageCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            if !hasKey {
                keyEntry
            }

            pageRange

            if let resultURL {
                resultPlayer(resultURL)
            }

            if isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .onDisappear { player?.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Make a Podcast", systemImage: "waveform.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text("Two AI hosts discuss the pages you pick. \(paperTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gemini API key").font(.subheadline.weight(.medium))
            HStack {
                SecureField("Paste your Gemini API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveKey() }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Stored only in your Keychain. Get a key at aistudio.google.com.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var pageRange: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Stepper(value: $fromPage, in: 1...pageCount) {
                Text("From page **\(fromPage)**")
            }
            Stepper(value: $toPage, in: 1...pageCount) {
                Text("To page **\(toPage)**")
            }
        }
        .font(.callout)
    }

    private func resultPlayer(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text("Podcast ready").font(.callout.weight(.medium))
                Text(durationLabel(resultDuration)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.08)))
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
            if resultURL != nil {
                Button("Add to Library") { addToLibrary() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            } else {
                Button {
                    generate()
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!hasKey || isWorking)
            }
        }
    }

    // MARK: - Actions

    private func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        KeychainService.set(key, for: KeychainService.Account.gemini)
        hasKey = true
        apiKeyInput = ""
    }

    private func generate() {
        errorText = nil
        isWorking = true
        detail = "Reading the pages…"
        let lo = min(fromPage, toPage)
        let hi = max(fromPage, toPage)
        let text = textForPages(lo, hi)
        Task {
            do {
                let result = try await GeminiPodcastService.shared.makePodcast(
                    title: paperTitle, sourceText: text
                ) { detail = $0 }
                resultURL = result.url
                resultDuration = result.durationSeconds
                player = try? AVAudioPlayer(contentsOf: result.url)
                player?.prepareToPlay()
                isWorking = false
            } catch {
                errorText = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func togglePlay() {
        guard let player else { return }
        if player.isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    private func addToLibrary() {
        guard let url = resultURL else { return }
        player?.stop()
        let item = DownloadItem(
            url: "podcast://\(UUID().uuidString)",
            title: "🎙️ \(paperTitle)",
            format: "Podcast",
            status: .completed,
            outputPath: url,
            consumptionMode: .download,
            durationSeconds: resultDuration
        )
        LibraryManager.shared.addDownload(item)
        dismiss()
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
