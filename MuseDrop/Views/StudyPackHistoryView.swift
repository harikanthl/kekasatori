//
//  StudyPackHistoryView.swift
//  MuseDrop
//

import SwiftUI
import AppKit

struct StudyPackHistoryView: View {
    @StateObject private var viewModel = StudyPackHistoryViewModel()
    @State private var playerWindowController: NSWindowController?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                ScreenHeader(
                    title: "Study Packs",
                    subtitle: "Every transcript and study pack you've generated",
                    systemImage: "text.book.closed"
                )

                controls

                if viewModel.filteredPacks.isEmpty {
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
            .frame(width: 150)
        }
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
        PlayerWindowPresenter.open(for: item, controller: &playerWindowController)
    }
}

private struct StudyPackHistoryRow: View {
    let pack: StudyPackSummary
    let viewModel: StudyPackHistoryViewModel
    let onOpen: () -> Void
    
    @State private var isHovered = false
    
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
                Button { share() } label: {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                Button { saveToDevice() } label: {
                    Label("Save to Device…", systemImage: "arrow.down.circle")
                }
            }
            .onHover { hovering in
                withAnimation(Theme.Motion.hover) { isHovered = hovering }
            }
    }

    private var rowContent: some View {
        Group {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                thumbnail

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
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
                        Button { share() } label: {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                        Button { saveToDevice() } label: {
                            Label("Save to Device…", systemImage: "arrow.down.circle")
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
    static func open(for item: DownloadItem, controller: inout NSWindowController?) {
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
        window.isReleasedWhenClosed = true
        
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
            }
        }

        observerTokens[item.id] = token
        openWindows[item.id] = windowController
        
        if let existing = controller, existing !== windowController {
            existing.close()
        }
        controller = windowController
        
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
