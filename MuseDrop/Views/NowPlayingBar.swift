//
//  NowPlayingBar.swift
//  Kekasatori
//
//  A persistent strip pinned to the bottom of the Library that reconnects the
//  separate player windows to the app. Reuses the retro terminal chrome from
//  `RetroStatusBar` (`.retroBarChrome` + `RetroPrompt`). Tapping the bar brings
//  the player window forward; the ✕ stops it. When several players are open the
//  front one shows with a "+N" badge. Renders nothing when nothing is open.
//

import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject private var center = NowPlayingCenter.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let entry = center.current {
                bar(entry)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: center.current)
    }

    private func bar(_ entry: NowPlayingCenter.Entry) -> some View {
        let tint = theme.accent
        let extras = center.entries.count - 1
        return HStack(spacing: 10) {
            RetroPrompt(paused: reduceMotion, tint: tint)

            Image(systemName: icon(for: entry))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 16)

            Text(label(for: entry))
                .foregroundStyle(tint.opacity(0.75))

            Text(entry.title)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)

            if extras > 0 {
                Text("+\(extras)")
                    .foregroundStyle(.white.opacity(0.5))
                    .help("\(extras) more player\(extras == 1 ? "" : "s") open")
            }

            Spacer(minLength: 8)

            Button {
                PlayerWindowPresenter.close(for: entry.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop and close player")
        }
        .font(.system(.caption, design: .monospaced).weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroBarChrome(tint: tint)
        .contentShape(Rectangle())
        .onTapGesture { PlayerWindowPresenter.focus(for: entry.id) }
        .help("Bring player window to front")
    }

    private func icon(for entry: NowPlayingCenter.Entry) -> String {
        if entry.isPaper { return "book.fill" }
        return entry.isPlaying ? "speaker.wave.2.fill" : "pause.fill"
    }

    private func label(for entry: NowPlayingCenter.Entry) -> String {
        entry.isPaper ? "READING" : "NOW PLAYING"
    }
}
