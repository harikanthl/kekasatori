//
//  RetroThinkingTicker.swift
//  Kekasatori
//
//  A small retro "message board" that rotates honest-but-playful status lines
//  while the user waits — a blinking terminal cursor, monospaced text, and a
//  pulsing trail. Used for the tutor's thinking state and study-pack generation
//  so waits feel alive rather than frozen. Respects Reduce Motion.
//

import SwiftUI

struct RetroThinkingTicker: View {
    let messages: [String]
    var tint: Color = Theme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var phase = 0

    private let blink = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let rotate = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    private var current: String { messages.isEmpty ? "Thinking" : messages[index % messages.count] }

    var body: some View {
        HStack(spacing: 8) {
            // Blinking cursor block.
            Rectangle()
                .fill(tint)
                .frame(width: 7, height: 15)
                .opacity(reduceMotion ? 1 : (phase % 2 == 0 ? 1 : 0.2))

            Text(current)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .lineLimit(1)
                .truncationMode(.tail)

            // Pulsing trail.
            Text(reduceMotion ? "…" : String(repeating: "•", count: (phase % 3) + 1))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tint.opacity(0.75))
                .frame(width: 22, alignment: .leading)
        }
        .onReceive(blink) { _ in phase &+= 1 }
        .onReceive(rotate) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.3)) { index &+= 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(current))
    }
}

// MARK: - Curated status lines

enum ThinkingLines {
    /// While the tutor composes an answer.
    static let tutor = [
        "Reading the source",
        "Thinking it through",
        "Connecting the ideas",
        "Finding the relevant parts",
        "Composing an answer"
    ]

    /// While the marimo notebook container spins up (first run installs the data stack).
    static let notebook = [
        "☕️ Brewing your notebook…",
        "📦 marimo + SQL engine (duckdb)…",
        "📊 dataframes — pandas, polars, pyarrow…",
        "📈 charts — numpy, matplotlib, altair…",
        "✅ All set — launching marimo, hold tight…",
    ]

    /// While a study pack is generated (the longer wait).
    static let generating = [
        "Skimming the abstract",
        "Highlighting the key parts",
        "Untangling the methods",
        "Drafting your notes",
        "Writing flashcards",
        "Distilling key concepts",
        "Sketching the mind map",
        "Polishing it up",
        "Almost there"
    ]
}
