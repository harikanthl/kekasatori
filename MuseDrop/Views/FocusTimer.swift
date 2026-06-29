//
//  FocusTimer.swift
//  Kekasatori
//
//  A Pomodoro-style focus timer with a retro analog dial, shown as a collapsible
//  corner widget while studying. Focus → short break cycles; completed focus
//  sessions are counted (and announced via the shared status bar). Kaizen-style:
//  small, repeated focused sessions rather than cramming.
//

import SwiftUI
import Combine

// MARK: - Model

@MainActor
final class FocusTimerModel: ObservableObject {
    static let shared = FocusTimerModel()

    enum Phase: Equatable {
        case idle, focus, shortBreak, longBreak

        var label: String {
            switch self {
            case .idle, .focus:   return "FOCUS"
            case .shortBreak:     return "BREAK"
            case .longBreak:      return "LONG BREAK"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var completedSessions = 0

    /// User-selectable focus length (minutes). Changing it while idle resets the clock.
    @Published var focusMinutes: Int = 25 {
        didSet { if phase == .idle { remaining = focusLength } }
    }
    /// Auto-start the next phase when one ends (classic Pomodoro flow).
    @Published var autoStartNext: Bool = true

    /// Selectable focus lengths shown in the picker.
    static let focusPresets = [5, 10, 15, 25, 50]

    let breakMinutes = 5
    let longBreakMinutes = 15
    /// A long break replaces the short break after this many focus sessions.
    let sessionsBeforeLongBreak = 4

    private var ticker: AnyCancellable?

    private var focusLength: TimeInterval { TimeInterval(focusMinutes * 60) }
    private var breakLength: TimeInterval { TimeInterval(breakMinutes * 60) }
    private var longBreakLength: TimeInterval { TimeInterval(longBreakMinutes * 60) }

    var total: TimeInterval {
        switch phase {
        case .longBreak:  return longBreakLength
        case .shortBreak: return breakLength
        default:          return focusLength
        }
    }

    /// Elapsed fraction (0…1) for the dial's sweep.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    var clockText: String {
        let s = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func startOrPause() { isRunning ? pause() : start() }

    func start() {
        if phase == .idle {
            phase = .focus
            remaining = focusLength
        }
        guard !isRunning else { return }
        isRunning = true
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        isRunning = false
        ticker?.cancel()
        ticker = nil
    }

    func reset() {
        pause()
        phase = .idle
        remaining = focusLength
    }

    /// Jump straight to the next phase (skip the rest of this one).
    func skip() { advancePhase() }

    private func tick() {
        guard isRunning else { return }
        remaining -= 1
        if remaining <= 0 { advancePhase() }
    }

    private func advancePhase() {
        switch phase {
        case .idle, .focus:
            if phase == .focus {
                completedSessions += 1
                let long = completedSessions % sessionsBeforeLongBreak == 0
                phase = long ? .longBreak : .shortBreak
                remaining = long ? longBreakLength : breakLength
                AppStatusCenter.shared.success(
                    "Focus session complete",
                    detail: "#\(completedSessions) · take a \(long ? longBreakMinutes : breakMinutes)-min break"
                )
            } else {
                phase = .shortBreak
                remaining = breakLength
            }
        case .shortBreak, .longBreak:
            AppStatusCenter.shared.info("Break over", detail: "back to focus")
            phase = .focus
            remaining = focusLength
        }
        if !autoStartNext { pause() }
    }
}

// MARK: - Corner widget

struct FocusTimerWidget: View {
    @ObservedObject private var model = FocusTimerModel.shared
    @ObservedObject private var theme = ThemeManager.shared
    @State private var expanded = false

    private var tint: Color {
        (model.phase == .shortBreak || model.phase == .longBreak)
            ? Color(red: 0.25, green: 0.70, blue: 0.45) : theme.accent
    }

    var body: some View {
        Button { expanded.toggle() } label: { launcherLabel }
            .buttonStyle(.plain)
            .help("Focus timer")
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                expandedCard
            }
    }

    // Collapsed: a small dial-faced toolbar button; shows the clock when active.
    private var launcherLabel: some View {
        ZStack {
            FocusDial(progress: model.progress, tint: tint, compact: true)
                .frame(width: 30, height: 30)
            if model.phase == .idle {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
            } else {
                Text(model.clockText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var expandedCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(model.phase.label)
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
                if model.completedSessions > 0 {
                    Text("● \(model.completedSessions)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Focus sessions completed")
                }
                Button { expanded = false } label: {
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
            }

            ZStack {
                FocusDial(progress: model.progress, tint: tint, compact: false)
                    .frame(width: 132, height: 132)
                Text(model.clockText)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 14) {
                control("arrow.counterclockwise", "Reset") { model.reset() }
                Button { model.startOrPause() } label: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(tint))
                        .shadow(color: tint.opacity(0.5), radius: 6)
                }
                .buttonStyle(.plain)
                .help(model.isRunning ? "Pause" : "Start")
                control("forward.end.fill", "Skip") { model.skip() }
            }

            Divider().overlay(.white.opacity(0.12))

            HStack(spacing: 8) {
                Image(systemName: "timer").font(.caption2).foregroundStyle(.white.opacity(0.5))
                Picker("Focus length", selection: $model.focusMinutes) {
                    ForEach(FocusTimerModel.focusPresets, id: \.self) { Text("\($0)m").tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .tint(tint)
                .disabled(model.isRunning)
                Spacer()
                Toggle("Auto", isOn: $model.autoStartNext)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(tint)
                    .help("Auto-start the next phase (long break every \(model.sessionsBeforeLongBreak) sessions)")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(14)
        .frame(width: 184)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.06, green: 0.07, blue: 0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.30), radius: 12, y: 4)
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Retro dial

private struct FocusDial: View {
    let progress: Double
    let tint: Color
    let compact: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.04, green: 0.05, blue: 0.07))

            // Tick marks around the rim — analog dial feel.
            ForEach(0..<60) { i in
                Rectangle()
                    .fill(.white.opacity(i % 5 == 0 ? 0.30 : 0.12))
                    .frame(width: i % 5 == 0 ? 2 : 1, height: i % 5 == 0 ? 6 : 3)
                    .offset(y: -(compact ? 20 : 60))
                    .rotationEffect(.degrees(Double(i) / 60 * 360))
            }

            // Track + sweeping progress arc.
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: compact ? 3 : 6)
                .padding(compact ? 7 : 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: compact ? 3 : 6, lineCap: .round))
                .padding(compact ? 7 : 16)
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.7), radius: compact ? 2 : 5)
                .animation(.linear(duration: 0.4), value: progress)
        }
    }
}
