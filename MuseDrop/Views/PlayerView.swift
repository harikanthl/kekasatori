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
    
    private var isAudio: Bool {
        item.isAudioMedia
    }
    
    private var isResearchPaper: Bool {
        item.isResearchDocument
    }
    
    var body: some View {
        HStack(spacing: 0) {
            mediaColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            PanelResizeHandle(panelWidth: studyPanelWidthBinding)
            
            StudyToolsPanel(item: item, viewModel: viewModel)
                .frame(width: studyPanelWidthBinding.wrappedValue)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            FocusTimerWidget()
                .padding(20)
        }
        .frame(minWidth: 1020, minHeight: 620)
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
        VStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.35),
                                Color.purple.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 280, height: 280)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                
                if let thumbnail = item.thumbnail,
                   let image = NSImage(contentsOf: thumbnail) {
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
            
            Text(item.displayTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 420)
            
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .frame(height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: 480)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
