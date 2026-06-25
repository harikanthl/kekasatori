//
//  HomeView.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import SwiftUI
import Lottie
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var selectedTab: NavigationTab
    @State private var showClearRecentConfirmation = false
    @State private var showingYouTubeSearch = false

    private var headerSubtitle: String {
        switch viewModel.ingestionMode {
        case .research:
            return "Read papers, articles & books with study tools"
        case .download:
            return "Download media from 1000+ sources"
        case .streamOnly:
            return "Stream and generate study materials without saving video"
        }
    }

    private var frescoHero: some View {
        ZStack(alignment: .bottomLeading) {
            Image(themeManager.theme.heroImageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.62), .black.opacity(0.18), .clear],
                startPoint: .bottom,
                endPoint: .top
            )

            HStack(spacing: Theme.Spacing.md) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.22))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kekasatori")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(height: 210)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                frescoHero

                Picker("Mode", selection: $viewModel.ingestionMode) {
                    ForEach(HomeIngestionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                urlInputCard

                helperOrErrorSection

                if viewModel.ingestionMode == .research {
                    researchImportSection
                } else if viewModel.ingestionMode == .download {
                    downloadButtons
                } else {
                    streamButtons
                }

                inlineWaitSection

                recentSection
            }
            .screenColumn(maxWidth: 720)
            .padding(.vertical, Theme.Spacing.xxl)
        }
        .overlay(alignment: .center) {
            if viewModel.showingDownloadNotification,
               viewModel.isVideoDownload,
               viewModel.ingestionMode == .download {
                VStack(spacing: Theme.Spacing.lg) {
                    LottieAnimationView(animationName: "cat")

                    HomeWaitStatusCard(
                        title: viewModel.waitTitle,
                        detail: viewModel.waitDetailMessage,
                        elapsedLabel: viewModel.waitSubtitle,
                        compact: true
                    )
                }
                .transition(.opacity)
                .animation(Theme.Motion.spring, value: viewModel.showingDownloadNotification)
            }
        }
        .onChange(of: viewModel.shouldNavigateToDownloads) { _, shouldNavigate in
            guard shouldNavigate else { return }
            Task { @MainActor in
                selectedTab = .downloads
                viewModel.shouldNavigateToDownloads = false
            }
        }
        .onChange(of: viewModel.shouldNavigateToLibrary) { _, shouldNavigate in
            guard shouldNavigate else { return }
            Task { @MainActor in
                selectedTab = .library
                viewModel.shouldNavigateToLibrary = false
            }
        }
        .confirmationDialog(
            "Clear recent history?",
            isPresented: $showClearRecentConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                viewModel.clearRecentLinks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your recently used URLs from Home. Downloads and library items are not affected.")
        }
        .sheet(isPresented: $showingYouTubeSearch) {
            YouTubeSearchSheet { result in
                viewModel.urlInput = result.url
                viewModel.validateURL()
            }
        }
    }

    // MARK: - URL Input

    private var isCurrentInputValid: Bool {
        viewModel.ingestionMode == .research ? viewModel.isValidPaperInput : viewModel.isValidURL
    }

    private var urlInputCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader("Enter URL", systemImage: "link")

            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)

                    TextField(
                        viewModel.ingestionMode == .research
                            ? "Paste a paper, article, or book URL…"
                            : "https://youtube.com/watch?v=…",
                        text: $viewModel.urlInput
                    )
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onChange(of: viewModel.urlInput) { _, _ in
                        viewModel.validateURL()
                    }
                    .onSubmit { viewModel.goFromURLField() }

                    if !viewModel.urlInput.isEmpty {
                        Button(action: { viewModel.urlInput = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md - 2)
                .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(
                            viewModel.urlInput.isEmpty
                                ? Color.secondary.opacity(0.25)
                                : (isCurrentInputValid ? Theme.accent : Theme.danger.opacity(0.7)),
                            lineWidth: 1
                        )
                )

                Button {
                    showingYouTubeSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Search YouTube — no link needed")

                Button(action: { viewModel.goFromURLField() }) {
                    Text("Go")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
            }

            if !viewModel.urlInput.isEmpty && !isCurrentInputValid {
                Text(viewModel.ingestionMode == .research
                     ? "Enter a paper (arXiv/PubMed/DOI/PDF), article, or book URL."
                     : "That doesn't look like a valid URL.")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(Theme.Spacing.xl)
        .cardSurface()
    }

    // MARK: - Helper / Error

    @ViewBuilder
    private var helperOrErrorSection: some View {
        if let error = viewModel.errorMessage {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.danger)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        } else if viewModel.ingestionMode != .research && viewModel.isValidURL {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: viewModel.ingestionMode == .download ? "arrow.down.circle" : "play.circle")
                Text(viewModel.ingestionMode == .download
                     ? "Choose a format below to start downloading."
                     : "Stream in the player and generate study tools — nothing saved to disk.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .transition(.opacity)
        }
    }

    // MARK: - Inline Wait

    @ViewBuilder
    private var inlineWaitSection: some View {
        if viewModel.showingDownloadNotification,
           !(viewModel.isVideoDownload && viewModel.ingestionMode == .download) {
            HomeWaitStatusCard(
                title: viewModel.waitTitle,
                detail: viewModel.waitDetailMessage,
                elapsedLabel: viewModel.waitSubtitle
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Research

    private var researchImportSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                ActionTile(
                    title: "Import Link",
                    subtitle: "Paper · Article · Book",
                    icon: "doc.text.magnifyingglass",
                    isEnabled: viewModel.isValidPaperInput && !viewModel.isHomeOperationInProgress
                ) {
                    Task { await viewModel.importResearchPaper() }
                }

                ActionTile(
                    title: "Choose PDF",
                    subtitle: "Drop or browse files",
                    icon: "arrow.down.doc",
                    isEnabled: !viewModel.isHomeOperationInProgress
                ) {
                    viewModel.importPDFFile()
                }
            }

            Text("Papers (arXiv · PubMed · DOI · PDF) plus any web article or blog — and multi-chapter books/docs sites are crawled and combined into one studyable document.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in
                    viewModel.importDroppedPDF(url)
                }
            }
            return true
        }
    }

    // MARK: - Download / Stream

    private var downloadButtons: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ActionTile(
                title: "Audio",
                subtitle: "MP3 · AAC · WAV",
                icon: "waveform",
                isEnabled: viewModel.isValidURL && !viewModel.isHomeOperationInProgress
            ) {
                Task { await viewModel.download(type: .audio) }
            }

            ActionTile(
                title: "Video",
                subtitle: "MP4 · Best quality",
                icon: "play.rectangle",
                isEnabled: viewModel.isValidURL && !viewModel.isHomeOperationInProgress
            ) {
                Task { await viewModel.download(type: .video) }
            }
        }
    }

    private var streamButtons: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ActionTile(
                title: "Stream Audio",
                subtitle: "Listen · Study pack",
                icon: "waveform",
                isEnabled: viewModel.isValidURL && !viewModel.isHomeOperationInProgress
            ) {
                Task { await viewModel.streamAndStudy(kind: .audio) }
            }

            ActionTile(
                title: "Stream Video",
                subtitle: "Watch · Study pack",
                icon: "play.circle",
                isEnabled: viewModel.isValidURL && !viewModel.isHomeOperationInProgress
            ) {
                Task { await viewModel.streamAndStudy(kind: .video) }
            }
        }
    }

    // MARK: - Recent

    @ViewBuilder
    private var recentSection: some View {
        if !viewModel.recentLinks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(
                    "Recent",
                    systemImage: "clock",
                    trailing: AnyView(
                        Button("Clear") {
                            showClearRecentConfirmation = true
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    )
                )

                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(viewModel.recentLinks.prefix(5).enumerated()), id: \.offset) { index, link in
                        RecentLinkRow(link: link, index: index) {
                            viewModel.urlInput = link
                            viewModel.validateURL()
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
                .cardSurface()
            }
        }
    }
}

// MARK: - Wait Status

private struct HomeWaitStatusCard: View {
    let title: String
    let detail: String
    let elapsedLabel: String
    var compact: Bool = false

    var body: some View {
        VStack(spacing: compact ? Theme.Spacing.sm : Theme.Spacing.md) {
            ProgressView()
                .controlSize(compact ? .regular : .small)

            Text(title)
                .font(compact ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(elapsedLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, compact ? Theme.Spacing.xl : Theme.Spacing.lg)
        .padding(.vertical, compact ? Theme.Spacing.lg : Theme.Spacing.md)
        .frame(maxWidth: compact ? 320 : .infinity)
        .floatingChrome(radius: Theme.Radius.card)
    }
}

// MARK: - Action Tile

struct ActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)

                VStack(spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
            .cardSurface()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(isHovered ? 0.5 : 0), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(Theme.Motion.hover, value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
        .onHover { isHovered = $0 && isEnabled }
    }
}

// MARK: - Recent Link Row

struct RecentLinkRow: View {
    let link: String
    let index: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Text("\(index + 1)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(link)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(URL(string: link)?.host ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.hover, value: isHovered)
    }
}

// MARK: - Lottie Animation View
struct LottieAnimationView: NSViewRepresentable {
    let animationName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let animationView = Lottie.LottieAnimationView(name: animationName)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.loopMode = .loop
        animationView.contentMode = .scaleAspectFit
        animationView.play()

        view.addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.widthAnchor.constraint(equalToConstant: 300),
            animationView.heightAnchor.constraint(equalToConstant: 300),
            animationView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            animationView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed
    }
}
