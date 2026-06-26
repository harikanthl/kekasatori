//
//  HomeView.swift
//  MuseDrop
//
//  The home screen, redesigned around a single Spotlight-style command bar
//  (macOS 26 / Liquid Glass). One field replaces the old paste/search/YouTube/Go
//  cluster; mode is chosen up top (Stream · Research · Download); the format and
//  source actions reveal themselves contextually once a link is valid.
//

import SwiftUI
import Lottie
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var appStatus = AppStatusCenter.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Binding var selectedTab: NavigationTab
    @State private var showClearRecentConfirmation = false
    @State private var showingYouTubeSearch = false
    @FocusState private var fieldFocused: Bool

    private let tagline = "Turn anything you watch or read into a study session."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                frescoHero
                modePicker
                commandSection
                actionSection
                inlineWaitSection
                recentSection
            }
            .screenColumn(maxWidth: 760)
            .padding(.vertical, Theme.Spacing.xxl)
        }
        .overlay(alignment: .center) { downloadOverlay }
        .onChange(of: viewModel.shouldNavigateToDownloads) { _, go in
            guard go else { return }
            Task { @MainActor in selectedTab = .downloads; viewModel.shouldNavigateToDownloads = false }
        }
        .onChange(of: viewModel.shouldNavigateToLibrary) { _, go in
            guard go else { return }
            Task { @MainActor in selectedTab = .library; viewModel.shouldNavigateToLibrary = false }
        }
        .confirmationDialog(
            "Clear recent history?",
            isPresented: $showClearRecentConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { viewModel.clearRecentLinks() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your recently used URLs from Home. Downloads and library items are not affected.")
        }
        .sheet(isPresented: $showingYouTubeSearch) {
            YouTubeSearchSheet { result in
                viewModel.urlInput = result.url
                viewModel.validateURL()
                AppStatusCenter.shared.success("Loaded link", detail: result.title)
            }
        }
    }

    // MARK: - Header

    /// Theme-based hero banner: the selected theme's artwork with the brand mark
    /// and tagline overlaid. The artwork follows the user's chosen theme.
    private var frescoHero: some View {
        ZStack(alignment: .bottomLeading) {
            Image(themeManager.theme.heroImageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.64), .black.opacity(0.16), .clear],
                startPoint: .bottom,
                endPoint: .top
            )

            HStack(spacing: Theme.Spacing.md) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(.white.opacity(0.22))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kekasatori")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text(tagline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    // MARK: - Mode

    private var modePicker: some View {
        Picker("Mode", selection: $viewModel.ingestionMode) {
            ForEach(HomeIngestionMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
    }

    // MARK: - Command bar

    private var isCurrentInputValid: Bool {
        viewModel.ingestionMode == .research ? viewModel.isValidPaperInput : viewModel.isValidURL
    }

    private var placeholder: String {
        switch viewModel.ingestionMode {
        case .streamOnly: return "Paste a link to stream & study…"
        case .research:   return "Paste a paper, article, or book URL…"
        case .download:   return "Paste a link to download…"
        }
    }

    private var borderColor: Color {
        if viewModel.urlInput.isEmpty { return fieldFocused ? Theme.accent.opacity(0.55) : .secondary.opacity(0.22) }
        return isCurrentInputValid ? Theme.accent : Theme.danger.opacity(0.7)
    }

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            commandBar
            RetroStatusBar(status: appStatus.status)
            if let error = viewModel.errorMessage {
                inlineNote(error, icon: "exclamationmark.triangle.fill", color: Theme.danger)
            } else if !viewModel.urlInput.isEmpty && !isCurrentInputValid {
                inlineNote(
                    viewModel.ingestionMode == .research
                        ? "Enter a paper (arXiv · PubMed · DOI · PDF), article, or book URL."
                        : "That doesn't look like a valid URL.",
                    icon: "info.circle", color: .secondary
                )
            }
        }
    }

    private var commandBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "link")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isCurrentInputValid ? Theme.accent : .secondary)
                .frame(width: 22)

            TextField(placeholder, text: $viewModel.urlInput)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($fieldFocused)
                .onChange(of: viewModel.urlInput) { _, _ in viewModel.validateURL() }
                .onSubmit { viewModel.goFromURLField() }

            // Consolidated trailing controls — replaces the old separate buttons.
            if viewModel.urlInput.isEmpty {
                iconButton("doc.on.clipboard", help: "Paste from clipboard") {
                    viewModel.pasteFromClipboard()
                }
            } else {
                iconButton("xmark.circle.fill", help: "Clear", tint: .tertiary) {
                    viewModel.urlInput = ""
                }
            }

            if viewModel.ingestionMode != .research {
                iconButton("magnifyingglass", help: "Search YouTube — no link needed") {
                    showingYouTubeSearch = true
                }
            }

            Button(action: { viewModel.goFromURLField() }) {
                Image(systemName: "arrow.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .clipShape(Circle())
            .help("Go")
            .disabled(viewModel.urlInput.isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .floatingChrome(radius: Theme.Radius.pill)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
        .shadow(color: Theme.accent.opacity(fieldFocused ? 0.18 : 0), radius: 14, y: 4)
        .animation(Theme.Motion.hover, value: fieldFocused)
        .animation(Theme.Motion.hover, value: viewModel.urlInput.isEmpty)
    }

    @ViewBuilder
    private func iconButton(_ symbol: String, help: String, tint: HierarchicalShapeStyle = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func inlineNote(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.xs)
        .transition(.opacity)
    }

    // MARK: - Contextual actions

    @ViewBuilder
    private var actionSection: some View {
        switch viewModel.ingestionMode {
        case .streamOnly:
            actionChips([
                ChipSpec(title: "Stream Audio", subtitle: "Listen · build a study pack", icon: "waveform",
                         enabled: viewModel.isValidURL) { Task { await viewModel.streamAndStudy(kind: .audio) } },
                ChipSpec(title: "Stream Video", subtitle: "Watch · build a study pack", icon: "play.circle",
                         enabled: viewModel.isValidURL) { Task { await viewModel.streamAndStudy(kind: .video) } }
            ])
        case .download:
            actionChips([
                ChipSpec(title: "Audio", subtitle: "MP3 · AAC · WAV", icon: "waveform",
                         enabled: viewModel.isValidURL) { Task { await viewModel.download(type: .audio) } },
                ChipSpec(title: "Video", subtitle: "MP4 · best quality", icon: "play.rectangle",
                         enabled: viewModel.isValidURL) { Task { await viewModel.download(type: .video) } }
            ])
        case .research:
            researchActions
        }
    }

    private func actionChips(_ specs: [ChipSpec]) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in
                ActionChip(spec: spec, busy: viewModel.isHomeOperationInProgress)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(Theme.Motion.spring, value: viewModel.isValidURL)
    }

    private var researchActions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                ActionChip(spec: ChipSpec(
                    title: "Import Link", subtitle: "Paper · article · book", icon: "doc.text.magnifyingglass",
                    enabled: viewModel.isValidPaperInput && !viewModel.isHomeOperationInProgress
                ) { Task { await viewModel.importResearchPaper() } }, busy: viewModel.isHomeOperationInProgress)

                ActionChip(spec: ChipSpec(
                    title: "Choose PDF", subtitle: "Drop or browse files", icon: "arrow.down.doc",
                    enabled: !viewModel.isHomeOperationInProgress
                ) { viewModel.importPDFFile() }, busy: false)
            }
            Text("Papers (arXiv · PubMed · DOI · PDF) plus any article or blog — multi-chapter books and docs sites are crawled and combined into one studyable document.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in viewModel.importDroppedPDF(url) }
            }
            return true
        }
    }

    // MARK: - Wait / overlay

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

    @ViewBuilder
    private var downloadOverlay: some View {
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

    // MARK: - Recent

    @ViewBuilder
    private var recentSection: some View {
        if !viewModel.recentLinks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(
                    "Recent",
                    systemImage: "clock.arrow.circlepath",
                    trailing: AnyView(
                        Button("Clear") { showClearRecentConfirmation = true }
                            .buttonStyle(.borderless)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    )
                )

                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(viewModel.recentLinks.prefix(6).enumerated()), id: \.offset) { _, link in
                        RecentLinkRow(link: link) {
                            viewModel.urlInput = link
                            viewModel.validateURL()
                            fieldFocused = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Action chip

struct ChipSpec {
    let title: String
    let subtitle: String
    let icon: String
    let enabled: Bool
    let action: () -> Void
}

struct ActionChip: View {
    let spec: ChipSpec
    var busy: Bool = false
    @State private var isHovered = false

    var body: some View {
        Button(action: spec.action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: spec.icon)
                    .font(.system(size: 22, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(spec.title).font(.headline).foregroundStyle(.primary)
                    Text(spec.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity)
            .cardSurface()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(isHovered && spec.enabled ? 0.5 : 0), lineWidth: 1)
            )
            .scaleEffect(isHovered && spec.enabled ? 1.01 : 1)
            .animation(Theme.Motion.hover, value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!spec.enabled)
        .opacity(spec.enabled ? 1 : 0.45)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recent link row

struct RecentLinkRow: View {
    let link: String
    let action: () -> Void
    @State private var isHovered = false

    private var host: String { URL(string: link)?.host?.replacingOccurrences(of: "www.", with: "") ?? link }
    private var source: (icon: String, color: Color) { RecentLinkRow.source(for: host) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: source.icon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(source.color)
                    .frame(width: 30, height: 30)
                    .background(source.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(host)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(prettyPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(isHovered ? Color.secondary.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.hover, value: isHovered)
    }

    private var prettyPath: String {
        guard let url = URL(string: link) else { return link }
        let path = url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let tail = (path.isEmpty || path == "/") ? (query.isEmpty ? link : query) : path + query
        return tail
    }

    static func source(for host: String) -> (icon: String, color: Color) {
        let h = host.lowercased()
        if h.contains("youtu") { return ("play.rectangle.fill", .red) }
        if h.contains("arxiv") { return ("doc.text.fill", .orange) }
        if h.contains("pubmed") || h.contains("ncbi") || h.contains("doi") { return ("cross.case.fill", .teal) }
        if h.contains("vimeo") { return ("play.rectangle.fill", .blue) }
        if h.contains("spotify") || h.contains("soundcloud") { return ("waveform", .green) }
        if h.contains("github") { return ("chevron.left.forwardslash.chevron.right", .purple) }
        if h.contains("wikipedia") { return ("character.book.closed.fill", .secondary) }
        return ("globe", Theme.accent)
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

    func updateNSView(_ nsView: NSView, context: Context) {}
}
