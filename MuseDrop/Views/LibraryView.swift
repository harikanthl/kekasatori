//
//  LibraryView.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import SwiftUI
import AppKit

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var playerWindowController: NSWindowController?
    @State private var itemPendingDeletion: DownloadItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ScreenHeader(
                        title: "Library",
                        systemImage: "square.stack.3d.up"
                    )
                    SectionRule()
                }
                .screenColumn()
                .padding(.top, Theme.Spacing.xl)

                // Search and Filter Bar
                HStack(spacing: Theme.Spacing.md) {
                    SearchField(placeholder: "Search your library", text: $viewModel.searchText)

                    Picker("Filter", selection: $viewModel.selectedFilter) {
                        ForEach(LibraryViewModel.FilterType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .floatingChrome()
                .screenColumn()

                if viewModel.selectedItem != nil {
                    selectionToolbar
                        .screenColumn()
                }

                // Media Grid
                if !viewModel.filteredItems.isEmpty {
                    LibraryMediaGrid(
                        items: viewModel.filteredItems,
                        selectedItemID: viewModel.selectedItemID,
                        mastery: viewModel.masteryByDownload,
                        onSelect: { viewModel.select($0) },
                        onOpen: { openPlayerWindow(for: $0) },
                        onDelete: { confirmDelete($0) }
                    )
                    .screenColumn()
                } else if viewModel.searchText.isEmpty {
                    EmptyStateView(
                        systemImage: "photo.on.rectangle.angled",
                        title: "No media yet",
                        message: "Downloaded files and stream bookmarks appear here."
                    )
                    .screenColumn()
                } else {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No results found",
                        message: "Try a different search term."
                    )
                    .screenColumn()
                }

                Spacer(minLength: Theme.Spacing.xxl)
            }
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .confirmationDialog(
            "Delete \"\(itemPendingDeletion?.displayTitle ?? "this item")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let item = itemPendingDeletion else { return }
                Task { await viewModel.delete(item) }
                itemPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                itemPendingDeletion = nil
            }
        } message: {
            Text("This removes the file, study pack, canvas boards, and transcript from Kekasatori.")
        }
        .onDeleteCommand {
            if let selected = viewModel.selectedItem {
                confirmDelete(selected)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NowPlayingBar()
                .screenColumn()
        }
        .onAppear { viewModel.refreshMastery() }
    }
    
    private var selectionToolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let selected = viewModel.selectedItem {
                Text(selected.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: Theme.Spacing.sm)

                Button {
                    openPlayerWindow(for: selected)
                } label: {
                    Label("Open", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button(role: .destructive) {
                    confirmDelete(selected)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(Theme.danger)
                .disabled(viewModel.isDeleting)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .floatingChrome()
    }
    
    private func confirmDelete(_ item: DownloadItem) {
        itemPendingDeletion = item
        showDeleteConfirmation = true
    }
}

// MARK: - Library Grid

private struct LibraryMediaGrid: View {
    let items: [DownloadItem]
    let selectedItemID: UUID?
    let mastery: [UUID: MasteryStage]
    let onSelect: (DownloadItem) -> Void
    let onOpen: (DownloadItem) -> Void
    let onDelete: (DownloadItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 300), spacing: Theme.Spacing.lg)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(items) { item in
                ModernMediaCard(
                    item: item,
                    isSelected: selectedItemID == item.id,
                    masteryStage: mastery[item.id],
                    onSelect: { onSelect(item) },
                    onOpen: { onOpen(item) },
                    onDelete: { onDelete(item) }
                )
            }
        }
    }
}

// MARK: - Thumbnail loading

/// File-scoped (non–main-actor) async thumbnail loader with an in-memory cache,
/// so library cards don't read image files synchronously in their view body.
private enum ThumbnailLoader {
    static let cache = NSCache<NSURL, NSImage>()

    static func load(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        return await Task.detached(priority: .utility) {
            guard let image = NSImage(contentsOf: url) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        }.value
    }
}

// MARK: - Modern Media Card
struct ModernMediaCard: View {
    let item: DownloadItem
    var isSelected: Bool = false
    var masteryStage: MasteryStage? = nil
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var canvasThumbURL: URL?
    @State private var loadedThumbnail: NSImage?
    @State private var isHovering = false

    private let thumbnailHeight: CGFloat = 160

    init(
        item: DownloadItem,
        isSelected: Bool = false,
        masteryStage: MasteryStage? = nil,
        onSelect: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.masteryStage = masteryStage
        self.onSelect = onSelect
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailSection
            cardContent
        }
        .cardSurface()
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
            }
        }
        .shadow(color: isSelected ? Theme.accent.opacity(0.18) : .clear, radius: 8, y: 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(Theme.Motion.hover, value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onOpen)
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .task {
            canvasThumbURL = await DataStore.shared.canvasPersistence.firstThumbnailURL(for: item.id)
        }
        .task(id: item.thumbnail) {
            loadedThumbnail = await ThumbnailLoader.load(item.thumbnail)
        }
    }

    private var thumbnailSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = loadedThumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if item.isResearchDocument {
                    // Papers aren't playable — papercraft art, never a play glyph.
                    Image("ThumbAI")
                        .resizable()
                        .scaledToFill()
                } else if item.isAudioMedia {
                    Image("ThumbAudio")
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "play.circle")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(.secondary)
                                .symbolRenderingMode(.hierarchical)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: thumbnailHeight)
            .clipped()
            .overlay(alignment: .topLeading) {
                if item.isStreamOnly {
                    Image(systemName: "icloud.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .symbolRenderingMode(.hierarchical)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(Theme.Spacing.sm)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let canvasThumbURL,
                   let image = NSImage(contentsOf: canvasThumbURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 1)
                        }
                        .shadow(radius: 2)
                        .padding(Theme.Spacing.sm)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let stage = masteryStage {
                    Label(stage.label, systemImage: stage.glyph)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stage.tint)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(Theme.Spacing.sm)
                }
            }

            Text(item.displayFormat)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity)
        .frame(height: thumbnailHeight)
        .background(.quaternary)
        .clipShape(
            .rect(
                topLeadingRadius: Theme.Radius.card,
                topTrailingRadius: Theme.Radius.card
            )
        )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 44, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Theme.Spacing.xs + 2) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(formatDate(item.createdDate))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Player Window Presentation
extension LibraryView {
    /// Opens the selected media item in its own macOS window, using the system's standard
    /// close / minimize / zoom / fullscreen controls in the title bar, per macOS HIG.
    func openPlayerWindow(for item: DownloadItem) {
        PlayerWindowPresenter.open(for: item, controller: $playerWindowController)
    }
}

// MARK: - Helper for Rounded Corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }

    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        self.init()

        let topLeft = rect.origin
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        if corners.contains(.topLeft) {
            move(to: CGPoint(x: topLeft.x + cornerRadii.width, y: topLeft.y))
        } else {
            move(to: topLeft)
        }

        if corners.contains(.topRight) {
            line(to: CGPoint(x: topRight.x - cornerRadii.width, y: topRight.y))
            curve(to: CGPoint(x: topRight.x, y: topRight.y + cornerRadii.height),
                  controlPoint1: topRight,
                  controlPoint2: topRight)
        } else {
            line(to: topRight)
        }

        if corners.contains(.bottomRight) {
            line(to: CGPoint(x: bottomRight.x, y: bottomRight.y - cornerRadii.height))
            curve(to: CGPoint(x: bottomRight.x - cornerRadii.width, y: bottomRight.y),
                  controlPoint1: bottomRight,
                  controlPoint2: bottomRight)
        } else {
            line(to: bottomRight)
        }

        if corners.contains(.bottomLeft) {
            line(to: CGPoint(x: bottomLeft.x + cornerRadii.width, y: bottomLeft.y))
            curve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - cornerRadii.height),
                  controlPoint1: bottomLeft,
                  controlPoint2: bottomLeft)
        } else {
            line(to: bottomLeft)
        }

        if corners.contains(.topLeft) {
            line(to: CGPoint(x: topLeft.x, y: topLeft.y + cornerRadii.height))
            curve(to: CGPoint(x: topLeft.x + cornerRadii.width, y: topLeft.y),
                  controlPoint1: topLeft,
                  controlPoint2: topLeft)
        } else {
            close()
        }
    }
}

struct UIRectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

