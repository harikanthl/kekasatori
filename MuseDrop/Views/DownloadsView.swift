//
//  DownloadsView.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import SwiftUI

struct DownloadsView: View {
    @StateObject private var viewModel = DownloadsViewModel()

    private var isEmpty: Bool {
        viewModel.activeDownloads.isEmpty &&
        viewModel.completedDownloads.isEmpty &&
        viewModel.failedDownloads.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                ScreenHeader(
                    title: "Downloads",
                    subtitle: "Track active, completed, and failed downloads",
                    systemImage: "arrow.down.circle"
                )

                if isEmpty {
                    EmptyStateView(
                        systemImage: "tray",
                        title: "No downloads yet",
                        message: "Start downloading from the Home tab."
                    )
                } else {
                    if !viewModel.activeDownloads.isEmpty {
                        section(
                            title: "Active",
                            systemImage: "arrow.down.circle",
                            tint: Theme.accent,
                            items: viewModel.activeDownloads
                        )
                    }

                    if !viewModel.completedDownloads.isEmpty {
                        section(
                            title: "Completed",
                            systemImage: "checkmark.circle.fill",
                            tint: Theme.success,
                            items: viewModel.completedDownloads
                        )
                    }

                    if !viewModel.failedDownloads.isEmpty {
                        section(
                            title: "Failed",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: Theme.danger,
                            items: viewModel.failedDownloads
                        )
                    }
                }
            }
            .screenColumn()
            .padding(.vertical, Theme.Spacing.xxl)
        }
        .alert(
            "Download Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        systemImage: String,
        tint: Color,
        items: [DownloadItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title, systemImage: systemImage, tint: tint)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    ModernDownloadCard(item: item, viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Modern Download Card

struct ModernDownloadCard: View {
    let item: DownloadItem
    let viewModel: DownloadsViewModel

    @State private var isHovered = false

    private var isActive: Bool {
        item.status == .downloading ||
        item.status == .merging ||
        item.status == .converting
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            thumbnail

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(item.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Spacing.sm) {
                    StatusPill(
                        text: Theme.label(for: item.status),
                        systemImage: Theme.icon(for: item.status),
                        color: Theme.color(for: item.status)
                    )
                    StatusPill(
                        text: item.displayFormat,
                        systemImage: "doc",
                        color: .secondary
                    )
                }

                if isActive {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        ProgressView(value: item.progress)
                            .progressViewStyle(.linear)
                            .tint(Theme.accent)
                            .animation(Theme.Motion.hover, value: item.progress)

                        Text("\(Int(item.progress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.top, Theme.Spacing.xs)
                }

                if item.status == .failed, let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.xs)
                }
            }

            Spacer(minLength: 0)

            actions
        }
        .padding(Theme.Spacing.lg)
        .cardSurface()
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(Theme.Motion.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }

    // MARK: Thumbnail

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let thumbnail = item.thumbnail,
               let image = NSImage(contentsOf: thumbnail) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: Theme.icon(for: item.status))
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if isActive {
            Button {
                viewModel.cancelDownload(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.7)
            .help("Cancel download")
        } else if item.status == .failed {
            Button {
                Task { await viewModel.retryDownload(item) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .help("Retry download")
        } else if item.status == .completed {
            Button {
                FileUtils.revealInFinder(item.outputPath)
            } label: {
                Image(systemName: "folder")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.7)
            .help("Show in Finder")
        }
    }
}
