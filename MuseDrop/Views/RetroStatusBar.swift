//
//  RetroStatusBar.swift
//  Kekasatori
//
//  A reusable, app-wide status/announcement strip with a terminal/CRT vibe:
//  monospace text, a blinking `>` prompt, themed-accent glow, and — for
//  long-running work — rotating playful loading words ("Combobulating…").
//
//  Two ways to use it:
//   • Drive it directly from local view state:  RetroStatusBar(status: someStatus)
//   • Drive it app-wide via the shared center:   AppStatusCenter.shared.working(…)
//     and mount  RetroStatusBar(status: appStatus.status)  somewhere persistent.
//

import SwiftUI

// MARK: - Model

/// A single message rendered by a `RetroStatusBar`.
struct RetroStatus: Equatable, Identifiable {
    enum Kind: Equatable {
        case working   // long-running task — animated, rotating playful words
        case info
        case success
        case warning

        var symbol: String {
            switch self {
            case .working: return "hourglass"
            case .info:    return "info.circle.fill"
            case .success: return "checkmark.seal.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }

        /// Fixed tints read as "status"; working/info defer to the app accent.
        func tint(accent: Color) -> Color {
            switch self {
            case .working, .info: return accent
            case .success:        return Color(red: 0.30, green: 0.78, blue: 0.45)
            case .warning:        return Color(red: 0.95, green: 0.62, blue: 0.23)
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var message: String
    var detail: String?

    init(kind: Kind, message: String, detail: String? = nil) {
        self.kind = kind
        self.message = message
        self.detail = detail
    }

    /// Identity-independent equality so an unchanged status doesn't re-animate.
    static func == (lhs: RetroStatus, rhs: RetroStatus) -> Bool {
        lhs.kind == rhs.kind && lhs.message == rhs.message && lhs.detail == rhs.detail
    }
}

// MARK: - Shared center

/// App-wide, ephemeral status messages. Post from anywhere; mount a
/// `RetroStatusBar(status: AppStatusCenter.shared.status)` where it should show.
@MainActor
final class AppStatusCenter: ObservableObject {
    static let shared = AppStatusCenter()

    @Published private(set) var status: RetroStatus?

    private var dismissTask: Task<Void, Never>?

    /// Sticky until cleared — for ongoing work.
    func working(_ message: String, detail: String? = nil) {
        set(RetroStatus(kind: .working, message: message, detail: detail), dismissAfter: nil)
    }

    func info(_ message: String, detail: String? = nil) {
        set(RetroStatus(kind: .info, message: message, detail: detail), dismissAfter: 4)
    }

    func success(_ message: String, detail: String? = nil) {
        set(RetroStatus(kind: .success, message: message, detail: detail), dismissAfter: 3)
    }

    func warning(_ message: String, detail: String? = nil) {
        set(RetroStatus(kind: .warning, message: message, detail: detail), dismissAfter: 6)
    }

    func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.snappy) { status = nil }
    }

    private func set(_ status: RetroStatus, dismissAfter seconds: Double?) {
        dismissTask?.cancel()
        withAnimation(.snappy) { self.status = status }
        guard let seconds else { dismissTask = nil; return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }
}

// MARK: - Bar

struct RetroStatusBar: View {
    let status: RetroStatus?

    var body: some View {
        ZStack {
            if let status {
                RetroStatusContent(status: status)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: status)
    }
}

// MARK: - Content

private struct RetroStatusContent: View {
    let status: RetroStatus

    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Playful verbs swapped in while work is in flight.
    private static let workingWords = [
        "Combobulating", "Conjugating", "Transmogrifying", "Percolating",
        "Finagling", "Localizing", "Noodling", "Marinating", "Pondering", "Whirring",
    ]

    private var tint: Color { status.kind.tint(accent: theme.accent) }

    var body: some View {
        HStack(spacing: 8) {
            leading

            HStack(spacing: 6) {
                if status.kind == .working {
                    RotatingWord(words: Self.workingWords, paused: reduceMotion, tint: tint)
                    AnimatedDots(paused: reduceMotion)
                }

                Text(status.message)
                    .foregroundStyle(.white.opacity(0.92))

                if let detail = status.detail {
                    Text(detail)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .font(.system(.caption, design: .monospaced).weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.10))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.12))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.30), radius: 7)
    }

    @ViewBuilder
    private var leading: some View {
        if status.kind == .working {
            BlinkingPrompt(paused: reduceMotion, tint: tint)
        } else {
            Image(systemName: status.kind.symbol)
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Retro animation pieces

/// A terminal-style `>` that blinks like a cursor.
private struct BlinkingPrompt: View {
    let paused: Bool
    let tint: Color

    var body: some View {
        Group {
            if paused {
                Text(">").foregroundStyle(tint)
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let on = Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
                    Text(">")
                        .foregroundStyle(tint)
                        .opacity(on ? 1 : 0.25)
                }
            }
        }
        .font(.system(.caption, design: .monospaced).weight(.bold))
    }
}

/// Crossfades through a list of playful words.
private struct RotatingWord: View {
    let words: [String]
    let paused: Bool
    let tint: Color

    @State private var index = 0

    var body: some View {
        Text(words[index])
            .foregroundStyle(tint)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.35), value: index)
            .onReceive(Timer.publish(every: 1.9, on: .main, in: .common).autoconnect()) { _ in
                guard !paused, words.count > 1 else { return }
                index = (index + 1) % words.count
            }
    }
}

/// Cycles "" → "." → ".." → "..." with reserved width so nothing jitters.
private struct AnimatedDots: View {
    let paused: Bool

    var body: some View {
        Group {
            if paused {
                Text("…")
            } else {
                TimelineView(.periodic(from: .now, by: 0.4)) { context in
                    let n = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 4
                    Text(String(repeating: ".", count: n))
                }
            }
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(width: 16, alignment: .leading)
    }
}
