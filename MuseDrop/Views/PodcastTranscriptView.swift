//
//  PodcastTranscriptView.swift
//  Kekasatori
//
//  Apple-Podcasts-style transcript: speaker-labeled lines, the currently-spoken
//  line at full weight with the rest dimmed, auto-scroll to keep it centered,
//  and tap-a-line-to-seek. Reduce-Motion aware.
//

import SwiftUI

struct PodcastTranscriptView: View {
    let lines: [PodcastTranscriptLine]
    let currentTime: Double
    let onSeek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Index of the line currently being spoken (last one whose start ≤ now).
    private var currentIndex: Int? {
        var result: Int?
        for (i, line) in lines.enumerated() {
            if line.start <= currentTime + 0.05 { result = i } else { break }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        lineView(line, active: index == currentIndex)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { onSeek(line.start) }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .onChange(of: currentIndex) { _, idx in
                guard let idx else { return }
                if reduceMotion {
                    proxy.scrollTo(idx, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(idx, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: PodcastTranscriptLine, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !line.speaker.isEmpty {
                Text(line.speaker.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(speakerColor(line.speaker))
            }
            Text(line.text)
                .font(.body)
                .fontWeight(active ? .semibold : .regular)
                .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .opacity(active ? 1 : 0.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    /// Deterministic two-tone by speaker so the two hosts read distinctly.
    private func speakerColor(_ speaker: String) -> Color {
        let sum = speaker.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum % 2 == 0 ? Theme.accent : Color(red: 0.25, green: 0.70, blue: 0.45)
    }
}
