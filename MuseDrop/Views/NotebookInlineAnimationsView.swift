//
//  NotebookInlineAnimationsView.swift
//  MuseDrop
//
//  Compact, bounded animation gallery: a single (optional) expanded player plus
//  a horizontally-scrolling thumbnail strip. Total height is fixed regardless of
//  how many animations exist, so it never grows tall under the notebook.
//

import SwiftUI
import AVKit

struct NotebookInlineAnimationsView: View {
    let downloadId: UUID
    let dayKey: String
    let animations: [NotebookAnimationRecord]
    var autoPlayId: UUID?
    var onDelete: (NotebookAnimationRecord) -> Void

    @State private var selectedId: UUID?
    @State private var maximizedRecord: NotebookAnimationRecord?
    @State private var players: [UUID: AVPlayer] = [:]
    @State private var loopObserver: NSObjectProtocol?

    private let stripHeight: CGFloat = 96
    private let playerMaxHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header

            if let selectedId, let record = animations.first(where: { $0.id == selectedId }) {
                expandedPlayer(record)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(animations) { record in
                        AnimationStripCell(
                            record: record,
                            isSelected: selectedId == record.id,
                            onTap: { select(record) },
                            onMaximize: { maximize(record) },
                            onDelete: { delete(record) }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .frame(height: stripHeight)
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(.separator.opacity(0.6))
        )
        .onAppear { playIfNeeded(autoPlayId) }
        .onDisappear { stopAll() }
        .onChange(of: autoPlayId) { _, newId in playIfNeeded(newId) }
        .sheet(item: $maximizedRecord) { record in
            MaximizedAnimationView(
                record: record,
                player: player(for: record),
                onClose: { maximizedRecord = nil }
            )
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "film.stack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text("Math animations")
                .font(.caption.weight(.semibold))
            Text("· \(animations.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func expandedPlayer(_ record: NotebookAnimationRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(record.latex)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    maximize(record)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Maximize")
                Button(role: .destructive) {
                    delete(record)
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Remove animation")
                Button {
                    collapse()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            NotebookLoopingVideoPlayer(player: player(for: record))
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: playerMaxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12))
                )
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
    }

    // MARK: Playback

    private func select(_ record: NotebookAnimationRecord) {
        if selectedId == record.id {
            collapse()
            return
        }
        stopLooping()
        pauseAll()
        selectedId = record.id
        let player = player(for: record)
        player.seek(to: .zero)
        startLooping(player)
    }

    private func collapse() {
        stopLooping()
        if let selectedId { players[selectedId]?.pause() }
        selectedId = nil
    }

    /// Opens the animation in a large sheet for clear viewing. Collapses the
    /// inline player first so a single AVPlayer isn't rendered in two places.
    private func maximize(_ record: NotebookAnimationRecord) {
        stopLooping()
        pauseAll()
        selectedId = nil
        maximizedRecord = record
    }

    private func playIfNeeded(_ id: UUID?) {
        guard let id, let record = animations.first(where: { $0.id == id }) else { return }
        select(record)
    }

    private func delete(_ record: NotebookAnimationRecord) {
        if selectedId == record.id { collapse() }
        players[record.id]?.pause()
        players.removeValue(forKey: record.id)
        onDelete(record)
    }

    private func player(for record: NotebookAnimationRecord) -> AVPlayer {
        if let existing = players[record.id] { return existing }
        let url = NotebookAnimationStore.resolvedVideoURL(for: record, downloadId: downloadId, dayKey: dayKey)
        let player = AVPlayer(url: url)
        players[record.id] = player
        return player
    }

    private func pauseAll() {
        for (_, player) in players { player.pause() }
    }

    private func stopAll() {
        stopLooping()
        pauseAll()
        selectedId = nil
    }

    private func startLooping(_ player: AVPlayer) {
        stopLooping()
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
    }

    private func stopLooping() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }
}

private struct AnimationStripCell: View {
    let record: NotebookAnimationRecord
    let isSelected: Bool
    let onTap: () -> Void
    let onMaximize: () -> Void
    let onDelete: () -> Void

    private let cellWidth: CGFloat = 150

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    Image(systemName: record.sceneType.icon)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .symbolRenderingMode(.hierarchical)
                    Image(systemName: isSelected ? "pause.circle.fill" : "play.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, Theme.accent)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .frame(width: cellWidth, height: 56)

                Text(record.latex)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: cellWidth, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
                .frame(width: cellWidth, height: 56, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
        )
        .help(record.sceneType.title)
        .contextMenu {
            Button { onMaximize() } label: {
                Label("Open Large", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Remove animation", systemImage: "trash")
            }
        }
    }
}

/// Large, looping presentation of a single animation so equations/numbers read
/// clearly. Minimize/close returns to the inline strip.
private struct MaximizedAnimationView: View {
    let record: NotebookAnimationRecord
    let player: AVPlayer
    let onClose: () -> Void

    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: record.sceneType.icon)
                    .foregroundStyle(Theme.accent)
                Text(record.latex)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                Spacer(minLength: Theme.Spacing.md)
                Button {
                    onClose()
                } label: {
                    Label("Minimize", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            NotebookLoopingVideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5))
                )
        }
        .padding(Theme.Spacing.lg)
        .frame(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 560)
        .onAppear { startLooping() }
        .onDisappear { stopLooping() }
    }

    private func startLooping() {
        stopLooping()
        player.seek(to: .zero)
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
    }

    private func stopLooping() {
        player.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }
}

private struct NotebookLoopingVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = player
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
