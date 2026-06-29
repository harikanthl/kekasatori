//
//  PlayerView.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import SwiftUI
import AVKit
import AppKit

struct PlayerView: View {
    let item: DownloadItem
    @StateObject private var viewModel = PlayerViewModel()
    // Wider default so the study tools (notebook, mind map) get real room.
    @AppStorage("studyPanelWidth") private var studyPanelWidth: Double = 560

    // Podcast transcript (loaded from the sidecar next to the audio).
    @State private var showTranscript = false
    @State private var transcript: PodcastTranscript?
    
    private var isAudio: Bool {
        item.isAudioMedia
    }
    
    private var isResearchPaper: Bool {
        item.isResearchDocument
    }
    
    var body: some View {
        Group {
            if item.isPodcast {
                // Focused listening player — no study panel.
                mediaColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    mediaColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    PanelResizeHandle(panelWidth: studyPanelWidthBinding)

                    StudyToolsPanel(item: item, viewModel: viewModel)
                        .frame(width: studyPanelWidthBinding.wrappedValue)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: item.isPodcast ? 400 : 1020, minHeight: item.isPodcast ? 540 : 620)
        .toolbar { toolbarContent }
        .onAppear {
            viewModel.prepare(for: item)
            viewModel.loadMedia(item)
        }
        .onChange(of: viewModel.isPlaying) { _, playing in
            NowPlayingCenter.shared.setPlaying(playing, for: item.id)
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .background {
            PlayerWindowLifecycle {
                viewModel.cleanup()
            }
        }
    }
    
    private var studyPanelWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(studyPanelWidth) },
            set: { studyPanelWidth = Double($0) }
        )
    }
    
    // MARK: - Media Column
    
    private var mediaColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsMediaMetadata {
                mediaMetadata
            }
            
            Group {
                if isResearchPaper {
                    PaperReaderView(item: item)
                } else if isAudio {
                    audioPlayerSection
                } else {
                    videoPlayerSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(isResearchPaper ? 12 : 24)
    }
    
    private var showsMediaMetadata: Bool {
        // Research papers own their own chrome in PaperReaderView, so we don't
        // repeat the format/filename strip (or the title) above the reader.
        guard !isResearchPaper else { return false }
        return viewModel.streamError != nil
            || item.isStreamOnly
            || item.outputPath != nil
    }
    
    private var mediaMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(item.displayFormat, systemImage: isResearchPaper ? "doc.text.fill" : (isAudio ? "waveform" : "film"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if item.isStreamOnly {
                    Label("Stream", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let path = item.outputPath {
                    Text(path.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            if let streamError = viewModel.streamError {
                Text(streamError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
    
    private var videoPlayerSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            
            if let ytID = viewModel.youtubeEmbedID {
                YouTubeEmbedView(videoID: ytID)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if let player = viewModel.player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if viewModel.isResolvingStream {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text(viewModel.streamResolveDetail ?? "Resolving stream…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
    
    private var audioPlayerSection: some View {
        VStack(spacing: 22) {
            if item.isPodcast, showTranscript, let transcript {
                PodcastTranscriptView(
                    lines: transcript.lines,
                    currentTime: viewModel.currentTime,
                    onSeek: { viewModel.seek(to: $0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                Spacer(minLength: 0)
                albumArt
                Text(item.displayTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 420)
                Spacer(minLength: 0)
            }

            if viewModel.player != nil {
                transportControls
            }

            if item.isPodcast, transcript != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showTranscript.toggle() }
                } label: {
                    Label(showTranscript ? "Now Playing" : "Transcript",
                          systemImage: showTranscript ? "music.note" : "text.quote")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .onAppear {
            if item.isPodcast, transcript == nil, let path = item.outputPath {
                transcript = PodcastTranscriptStore.load(for: path)
            }
        }
    }

    private var albumArt: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 280, height: 280)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)

            if let thumbnail = item.thumbnail, let image = NSImage(contentsOf: thumbnail) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: - Audio / podcast transport

    private var transportControls: some View {
        VStack(spacing: 18) {
            // Scrubber + times
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { viewModel.currentTime },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...max(viewModel.duration, 0.1)
                )
                .tint(Theme.accent)
                HStack {
                    Text(Self.timeLabel(viewModel.currentTime))
                    Spacer()
                    Text(Self.timeLabel(viewModel.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)

            // Skip / play / skip
            HStack(spacing: 30) {
                Button { viewModel.skip(-15) } label: {
                    Image(systemName: "gobackward.15").font(.title2)
                }
                .buttonStyle(.plain)
                .help("Back 15 seconds")

                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill"
                          : (viewModel.didReachEnd ? "arrow.counterclockwise.circle.fill" : "play.circle.fill"))
                        .font(.system(size: 54))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .help(viewModel.isPlaying ? "Pause" : (viewModel.didReachEnd ? "Replay" : "Play"))

                Button { viewModel.skip(15) } label: {
                    Image(systemName: "goforward.15").font(.title2)
                }
                .buttonStyle(.plain)
                .help("Forward 15 seconds")
            }

            // Speed
            Menu {
                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        viewModel.setPlaybackRate(rate)
                    } label: {
                        if viewModel.playbackRate == rate {
                            Label(Self.rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(rate))
                        }
                    }
                }
            } label: {
                Label(Self.rateLabel(viewModel.playbackRate), systemImage: "speedometer")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Playback speed")
        }
        .frame(maxWidth: 460)
    }

    private static func timeLabel(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func rateLabel(_ r: Double) -> String {
        r == r.rounded() ? "\(Int(r))×" : String(format: "%g×", r)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            FocusTimerWidget()
            if item.isStreamOnly {
                Button {
                    if let url = URL(string: item.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                
                Button {
                    Task { await viewModel.refreshStreamIfNeeded() }
                } label: {
                    Label("Refresh Stream", systemImage: "arrow.clockwise")
                }
            } else if let url = item.outputPath {
                Button {
                    FileUtils.openFile(url)
                } label: {
                    Label("Open", systemImage: "play.fill")
                }
                .help("Open with default app")
                
                Button {
                    FileUtils.revealInFinder(url)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Reveal file in Finder")
            }
        }
    }
}

// MARK: - Window lifecycle

/// Ensures playback stops when the player window closes. SwiftUI `onDisappear`
/// is not always delivered for `NSWindow` close, so we observe `willClose` directly.
private struct PlayerWindowLifecycle: NSViewRepresentable {
    let onWindowClose: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWindowClose = onWindowClose
        context.coordinator.attach(to: nsView)
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowClose: onWindowClose)
    }
    
    final class Coordinator {
        var onWindowClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?
        
        init(onWindowClose: @escaping () -> Void) {
            self.onWindowClose = onWindowClose
        }
        
        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = view.window else { return }
                guard self.observedWindow !== window else { return }
                self.detach()
                self.observedWindow = window
                self.closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.onWindowClose()
                }
            }
        }
        
        func detach() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }
            observedWindow = nil
        }
        
        deinit {
            detach()
        }
    }
}

// MARK: - Themed window root

/// Root for a player window's hosting controller. Player windows are separate
/// `NSHostingController`s, so — unlike the main window's `ContentView` — they
/// don't observe `ThemeManager` and never receive the accent tint. That left
/// native controls on the system accent and froze the accent at open time.
/// Observing here re-renders the window on theme change and applies the tint,
/// matching the main window. (Light/Dark already follows via `NSApp.appearance`.)
struct ThemedPlayerRoot: View {
    let item: DownloadItem
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        PlayerView(item: item)
            .tint(theme.accent)
    }
}
