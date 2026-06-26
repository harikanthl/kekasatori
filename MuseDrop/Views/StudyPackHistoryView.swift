//
//  StudyPackHistoryView.swift
//  MuseDrop
//

import SwiftUI
import AppKit

struct StudyPackHistoryView: View {
    @StateObject private var viewModel = StudyPackHistoryViewModel()
    @State private var playerWindowController: NSWindowController?
    @State private var showBoard = false
    @State private var showImportConfirmation = false
    @State private var importedCount = 0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                ScreenHeader(
                    title: "Study Packs",
                    subtitle: "Every transcript and study pack you've generated",
                    systemImage: "text.book.closed"
                )

                controls

                if showBoard {
                    StudyPackBoardView(viewModel: viewModel, onOpen: { openPack($0) })
                } else if viewModel.filteredPacks.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.filteredPacks) { pack in
                            StudyPackHistoryRow(pack: pack, viewModel: viewModel) {
                                openPack(pack)
                            }
                        }
                    }
                }

                Spacer(minLength: Theme.Spacing.xxl)
            }
            .screenColumn()
            .padding(.top, Theme.Spacing.xxl)
        }
        .onAppear {
            viewModel.reload()
        }
        .alert("Study pack imported", isPresented: $showImportConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importedCount == 1
                 ? "Added 1 study pack to your library."
                 : "Added \(importedCount) study packs to your library.")
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            SearchField(placeholder: "Search study packs…", text: $viewModel.searchText)

            Picker("Filter", selection: $viewModel.selectedFilter) {
                ForEach(StudyPackHistoryViewModel.Filter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)

            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(StudyPackHistoryViewModel.SortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: "arrow.up.arrow.down").tag(order)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 170)

            Picker("View", selection: $showBoard) {
                Image(systemName: "list.bullet").tag(false)
                Image(systemName: "rectangle.split.3x1").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Switch between list and mastery board")

            Spacer(minLength: Theme.Spacing.sm)

            Button { importPacks() } label: {
                Label("Import Pack…", systemImage: "square.and.arrow.down")
            }
            .help("Import a Kekasatori study pack (.kekapack) shared with you")
        }
    }

    @MainActor
    private func importPacks() {
        let packs = StudyPackExporter.importPacksFromDisk()
        guard !packs.isEmpty else { return }
        for pack in packs {
            DataStore.shared.importStudyPack(pack)
            if let root = pack.rootDirectory {
                try? FileManager.default.removeItem(at: root)
            }
        }
        viewModel.reload()
        importedCount = packs.count
        showImportConfirmation = true
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: viewModel.searchText.isEmpty ? "text.book.closed" : "magnifyingglass",
            title: viewModel.searchText.isEmpty ? "No study packs yet" : "No matching packs",
            message: viewModel.searchText.isEmpty
                ? "Generate a study pack from the player to see it here."
                : "Try a different search or filter."
        )
    }

    private func openPack(_ pack: StudyPackSummary) {
        guard let item = viewModel.downloadItem(for: pack) else { return }
        viewModel.markStudied(for: pack)
        PlayerWindowPresenter.open(for: item, controller: $playerWindowController)
    }
}

private struct StudyPackHistoryRow: View {
    let pack: StudyPackSummary
    let viewModel: StudyPackHistoryViewModel
    let onOpen: () -> Void

    @State private var isHovered = false
    @State private var composing = false
    @State private var pendingPackURL: URL?
    
    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAddTraits(.isButton)
            .contextMenu {
                Button { onOpen() } label: {
                    Label("Open", systemImage: "play.fill")
                }
                Divider()
                Menu {
                    ForEach(MasteryStage.allCases) { stage in
                        Button { viewModel.setMastery(stage, for: pack) } label: {
                            Label("\(stage.label) · \(stage.stageName)", systemImage: stage.glyph)
                        }
                    }
                    if pack.masteryStage != nil {
                        Divider()
                        Button("Clear stage") { viewModel.setMastery(nil, for: pack) }
                    }
                } label: {
                    Label("Mastery", systemImage: "circle.lefthalf.filled")
                }
                Button { viewModel.togglePin(for: pack) } label: {
                    Label(pack.isPinned ? "Unpin" : "Pin to top",
                          systemImage: pack.isPinned ? "star.slash" : "star")
                }
                Divider()
                Button { shareToCommunity() } label: {
                    Label("Share to Community…", systemImage: "person.3")
                }
                Button { exportPack() } label: {
                    Label("Export Pack…", systemImage: "shippingbox")
                }
                Button { share() } label: {
                    Label("Share as Markdown…", systemImage: "square.and.arrow.up")
                }
                Button { saveToDevice() } label: {
                    Label("Save Markdown…", systemImage: "arrow.down.circle")
                }
            }
            .onHover { hovering in
                withAnimation(Theme.Motion.hover) { isHovered = hovering }
            }
            .sheet(isPresented: $composing) {
                CommunityComposeSheet(
                    initialTitle: pack.displayTitle,
                    initialSummary: pack.summaryOneLine,
                    contentType: .studyPack,
                    onPublish: { title, summary, tags, category, communityId in
                        publishToCommunity(title: title, summary: summary, tags: tags,
                                           category: category, communityId: communityId)
                    },
                    onCancel: { cancelCommunityShare() }
                )
            }
    }

    private var rowContent: some View {
        Group {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                thumbnail

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Button { viewModel.togglePin(for: pack) } label: {
                            Image(systemName: pack.isPinned ? "star.fill" : "star")
                                .font(.subheadline)
                                .foregroundStyle(pack.isPinned
                                    ? Color(red: 0.95, green: 0.72, blue: 0.20)
                                    : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .opacity(pack.isPinned ? 1 : (isHovered ? 0.9 : 0.25))
                        .help(pack.isPinned ? "Unpin" : "Pin to top")

                        Text(pack.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: Theme.Spacing.sm)

                        if pack.isStreamOnly {
                            StatusPill(text: "Stream", systemImage: "icloud", color: .secondary)
                        }
                    }

                    if !pack.summaryOneLine.isEmpty {
                        Text(pack.summaryOneLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: Theme.Spacing.xs + 2) {
                        if let stage = pack.masteryStage {
                            StatusPill(text: stage.label, systemImage: stage.glyph, color: stage.tint)
                        }

                        StatusPill(
                            text: pack.statusLabel,
                            systemImage: pack.isCompletePack ? "checkmark.seal.fill" : "doc.text",
                            color: pack.isCompletePack ? Theme.success : Theme.idle
                        )

                        if pack.flashcardCount > 0 {
                            StatusPill(
                                text: "\(pack.flashcardCount) cards",
                                systemImage: "rectangle.on.rectangle.angled",
                                color: .secondary
                            )
                        }

                        if pack.noteSectionCount > 0 {
                            StatusPill(
                                text: "\(pack.noteSectionCount) notes",
                                systemImage: "note.text",
                                color: .secondary
                            )
                        }

                        if pack.conceptCount > 0 {
                            StatusPill(
                                text: "\(pack.conceptCount) terms",
                                systemImage: "lightbulb",
                                color: .secondary
                            )
                        }
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        if let lastGenerated = pack.lastGeneratedAt {
                            Label {
                                Text("Last \(viewModel.artifactLabel(for: pack.lastArtifactKindRaw)) · \(lastGenerated.formatted(.relative(presentation: .named)))")
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }

                        if pack.generationCount > 1 {
                            Text("\(pack.generationCount) generations")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Text(pack.engineLabel)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Menu {
                        Button { shareToCommunity() } label: {
                            Label("Share to Community…", systemImage: "person.3")
                        }
                        Button { exportPack() } label: {
                            Label("Export Pack…", systemImage: "shippingbox")
                        }
                        Divider()
                        Button { share() } label: {
                            Label("Share as Markdown…", systemImage: "square.and.arrow.up")
                        }
                        Button { saveToDevice() } label: {
                            Label("Save Markdown…", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .opacity(isHovered ? 1 : 0.4)
                    .help("Share or save this study pack")

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered ? 1 : 0)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func exportPack() {
        guard let export = DataStore.shared.makeStudyPackExport(
            for: pack.downloadId,
            sourceTitle: pack.displayTitle
        ) else { return }
        StudyPackExporter.savePackToDevice(export, suggestedName: pack.displayTitle)
    }

    /// Build the pack into a temp `.kekapack` and open the compose sheet.
    private func shareToCommunity() {
        guard let export = DataStore.shared.makeStudyPackExport(
            for: pack.downloadId,
            sourceTitle: pack.displayTitle
        ) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("community-share-\(UUID().uuidString).kekapack")
        do {
            try StudyPackExporter.writePack(export, to: tmp)
        } catch {
            return
        }
        pendingPackURL = tmp
        composing = true
    }

    private func publishToCommunity(title: String, summary: String, tags: [String],
                                    category: StudyCategory, communityId: String?) {
        guard let packURL = pendingPackURL else { return }
        let draft = CommunityPostDraft(
            contentType: .studyPack,
            title: title,
            summary: summary,
            tags: tags,
            author: CommunityIdentity.shared.author,
            packFileURL: packURL,
            category: category,
            communityId: communityId
        )
        composing = false
        pendingPackURL = nil
        Task {
            _ = try? await CommunityProvider.shared.publish(draft)
            try? FileManager.default.removeItem(at: packURL)
        }
    }

    private func cancelCommunityShare() {
        composing = false
        if let url = pendingPackURL {
            try? FileManager.default.removeItem(at: url)
            pendingPackURL = nil
        }
    }

    private func share() {
        guard let analysis = viewModel.analysis(for: pack) else { return }
        StudyPackExporter.share(analysis)
    }

    private func saveToDevice() {
        guard let analysis = viewModel.analysis(for: pack) else { return }
        StudyPackExporter.saveToDevice(analysis)
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let path = pack.thumbnailPath,
               let image = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(.quaternary)
                    Image(systemName: "text.book.closed")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

enum PlayerWindowPresenter {
    @MainActor
    private static var openWindows: [UUID: NSWindowController] = [:]
    @MainActor
    private static var observerTokens: [UUID: NSObjectProtocol] = [:]
    
    @MainActor
    static func open(for item: DownloadItem, controller: Binding<NSWindowController?>) {
        close(for: item.id)

        let hostingController = NSHostingController(rootView: PlayerView(item: item))

        let window = NSWindow(contentViewController: hostingController)
        window.title = item.displayTitle
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.minSize = NSSize(width: 980, height: 620)
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        // The NSWindowController + ARC own the window. With an owning controller,
        // isReleasedWhenClosed must be false — otherwise closing frees a window the
        // controller still references. ARC deallocates once every reference below
        // is dropped on close.
        window.isReleasedWhenClosed = false

        let windowController = NSWindowController(window: window)

        let itemId = item.id
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                // Remove the observer so its captured windowController/closure is freed.
                if let token = observerTokens.removeValue(forKey: itemId) {
                    NotificationCenter.default.removeObserver(token)
                }
                if openWindows[itemId] === windowController {
                    openWindows.removeValue(forKey: itemId)
                }
                // Drop the caller's reference too, so the controller — and its
                // window, hosting view, PlayerViewModel, and any web view —
                // deallocates instead of lingering (and playing) in the background.
                if controller.wrappedValue === windowController {
                    controller.wrappedValue = nil
                }
            }
        }

        observerTokens[item.id] = token
        openWindows[item.id] = windowController

        if let existing = controller.wrappedValue, existing !== windowController {
            existing.close()
        }
        controller.wrappedValue = windowController

        windowController.showWindow(nil)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    
    @MainActor
    static func close(for itemId: UUID) {
        guard let controller = openWindows[itemId] else { return }
        controller.close()
        openWindows.removeValue(forKey: itemId)
        if let token = observerTokens.removeValue(forKey: itemId) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
