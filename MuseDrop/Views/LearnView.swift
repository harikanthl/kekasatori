//
//  LearnView.swift
//  MuseDrop
//
//  The Learn tab — a learning-editor laid out the way LeetCode / exercism /
//  deep-ml do, native to macOS 26: a problem-list sidebar, a tabbed
//  Theory / Task description, the Monaco editor, and a results pane with the
//  Swift Charts loss visualiser. Panes are resizable (HSplitView / VSplitView).
//

import SwiftUI
import Charts

struct LearnView: View {
    /// Forwarded to the editor so its hidden web view doesn't leak the I-beam cursor
    /// onto other tabs when Learn isn't selected (see MonacoEditorView).
    var isActive: Bool = true
    @StateObject private var model = LearnViewModel()
    @Environment(\.colorScheme) private var colorScheme

    enum Pane: String, CaseIterable, Identifiable { case theory, task; var id: String { rawValue }
        var title: String { self == .theory ? "Theory" : "Task" } }
    @State private var pane: Pane = .theory
    /// nil → show the category landing grid; otherwise the drilled-in category.
    @State private var categoryID: String?

    private var selectedCategory: ChallengeStore.LearnCategory? {
        ChallengeStore.categories.first { $0.id == categoryID }
    }

    var body: some View {
        if let category = selectedCategory {
            HSplitView {
                sidebar(category)
                    .frame(minWidth: 232, idealWidth: 272, maxWidth: 340)
                content
                    .frame(minWidth: 540)
            }
        } else {
            catalog
        }
    }

    /// Enter a category, selecting its first challenge unless the current
    /// selection already lives inside it.
    private func open(_ category: ChallengeStore.LearnCategory) {
        guard !category.challenges.isEmpty else { return }
        categoryID = category.id
        pane = .theory
        if model.selected.map({ !category.modules.contains($0.module) }) ?? true {
            model.select(category.challenges.first)
        }
    }

    // MARK: - Catalog (landing grid of categories)

    private var catalog: some View {
        let columns = [GridItem(.adaptive(minimum: 260, maximum: 360),
                                spacing: Theme.Spacing.lg)]
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                ScreenHeader(
                    title: "Learn",
                    subtitle: "Build ML from the ground up — implement each piece and check it in a container.",
                    systemImage: "graduationcap.fill"
                )

                SectionRule()

                ProgressView(value: Double(model.completed.count),
                             total: Double(max(model.challenges.count, 1))) {
                    HStack {
                        Text("Overall progress").font(.caption.weight(.medium))
                        Spacer()
                        Text("\(model.completed.count) / \(model.challenges.count) lessons")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)

                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(ChallengeStore.categories) { category in
                        categoryCard(category)
                    }
                }
            }
            .screenColumn()
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    private func categoryCard(_ category: ChallengeStore.LearnCategory) -> some View {
        let challenges = category.challenges
        let total = challenges.count
        let done = challenges.filter { model.completed.contains($0.id) }.count
        let comingSoon = total == 0
        return Button { open(category) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: category.symbol)
                        .font(.title2)
                        .foregroundStyle(comingSoon ? Color.secondary : Theme.gold)
                        .frame(width: 30)
                    Spacer(minLength: Theme.Spacing.sm)
                    if comingSoon {
                        Text("Coming soon")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("\(done)/\(total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(done == total ? Theme.success : .secondary)
                    }
                }

                Text(category.name).font(.title3.weight(.semibold))
                Text(category.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Theme.Spacing.sm)

                if !comingSoon {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                        .tint(done == total ? Theme.success : Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(Theme.Spacing.lg)
            .cardSurface()
            .opacity(comingSoon ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(comingSoon)
    }

    // MARK: - Sidebar (problem list, scoped to the open category)

    private func sidebar(_ category: ChallengeStore.LearnCategory) -> some View {
        let challenges = category.challenges
        let done = challenges.filter { model.completed.contains($0.id) }.count
        let multiModule = category.modules.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Button { categoryID = nil } label: {
                    Label("All topics", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                HStack {
                    Label(category.name, systemImage: category.symbol)
                        .font(.title3.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                    Spacer()
                    Text("\(done)/\(challenges.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(done),
                             total: Double(max(challenges.count, 1)))
                    .tint(Theme.accent)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)

            SectionRule()

            List {
                ForEach(category.modules, id: \.self) { module in
                    let rows = challenges.filter { $0.module == module }
                    if multiModule {
                        Section(ChallengeStore.shortModuleName(module)) {
                            ForEach(rows) { challengeRow($0) }
                        }
                    } else {
                        ForEach(rows) { challengeRow($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 30)
        }
    }

    private func challengeRow(_ challenge: Challenge) -> some View {
        let isSelected = model.selected?.id == challenge.id
        return Button {
            model.select(challenge)
            pane = .theory
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: model.isCompleted(challenge) ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(model.isCompleted(challenge) ? Theme.success : Color.secondary)
                Text(challenge.title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                difficultyDot(challenge.difficulty)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Theme.accent.opacity(0.14) : Color.clear)
    }

    private func difficultyDot(_ difficulty: Challenge.Difficulty) -> some View {
        Circle().fill(color(difficulty)).frame(width: 7, height: 7)
    }

    private func color(_ difficulty: Challenge.Difficulty) -> Color {
        switch difficulty {
        case .easy: Theme.success
        case .medium: Theme.warning
        case .hard: Theme.danger
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let challenge = model.selected {
            VStack(spacing: 0) {
                toolbar(challenge)
                SectionRule()
                if let runtime = model.runtime, !runtime.isReady {
                    runtimeBanner(runtime)
                }
                HSplitView {
                    descriptionPane(challenge)
                        .frame(minWidth: 280, idealWidth: 380)
                    VSplitView {
                        editorPane
                            .frame(minWidth: 360, minHeight: 220)
                        resultsPane
                            .frame(minHeight: 150, idealHeight: 230)
                    }
                    .frame(minWidth: 360)
                }
            }
        } else {
            EmptyStateView(systemImage: "graduationcap",
                           title: "Pick a challenge",
                           message: "Implement ML building blocks from scratch and check them in a container.")
        }
    }

    private func toolbar(_ challenge: Challenge) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title).font(.title3.weight(.semibold))
                HStack(spacing: Theme.Spacing.sm) {
                    difficultyBadge(challenge.difficulty)
                    if let reference = challenge.reference {
                        Label(reference, systemImage: "book.closed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            switch model.result {
            case .passed: StatusPill(text: "Passed", systemImage: "checkmark.seal.fill", color: Theme.success)
            case .failed: StatusPill(text: "Try again", systemImage: "xmark.circle", color: Theme.danger)
            case nil: EmptyView()
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button { model.resetToStarter() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Reset to starter")
                    .disabled(model.isRunning)
                if model.isRunning {
                    Button(role: .cancel) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                } else {
                    Button { model.run(check: false) } label: { Label("Run", systemImage: "play") }
                        .disabled(!model.canRun)
                    Button { model.run(check: true) } label: { Label("Check", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canRun)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .floatingChrome(radius: Theme.Radius.md)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.md)
    }

    private func difficultyBadge(_ difficulty: Challenge.Difficulty) -> some View {
        Text(difficulty.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color(difficulty))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color(difficulty).opacity(0.14), in: Capsule())
    }

    // MARK: - Description (Theory / Task)

    private func descriptionPane(_ challenge: Challenge) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Theme.Spacing.md)

            SectionRule()

            ScrollView {
                MarkdownMessageView(text: pane == .theory
                    ? (challenge.theory.isEmpty ? challenge.prompt : challenge.theory)
                    : challenge.prompt)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.lg)
            }
        }
    }

    // MARK: - Editor & results

    private var editorPane: some View {
        let lang = model.selected?.language ?? .python
        let monacoLanguage = lang == .bash ? "shell" : "python"
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(lang.fileName, systemImage: "doc.text")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)

            MonacoEditorView(text: $model.code, language: monacoLanguage, dark: colorScheme == .dark, isActive: isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var resultsPane: some View {
        let series = model.lossSeries
        return VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Label("Output", systemImage: "terminal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if model.isRunning { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            SectionRule()

            if series.count > 1 {
                LossChartView(values: series)
                    .frame(height: 150)
                SectionRule()
            }

            ScrollView {
                Text(model.output.isEmpty ? "Run or Check to see container output." : model.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(model.output.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        }
    }

    private func runtimeBanner(_ runtime: ContainerRuntimeStatus) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text("\(runtime.statusMessage) — set it up in the Code tab.").font(.caption)
            Spacer(minLength: 0)
            Button("Re-check") { model.checkRuntime() }.controlSize(.small)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.warning.opacity(0.08))
    }
}

// MARK: - Loss visualiser (Swift Charts)

private struct LossChartView: View {
    let values: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Loss curve")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)

            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Step", index), y: .value("Loss", value))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Step", index), y: .value("Loss", value))
                    .foregroundStyle(Theme.accent.opacity(0.12))
                    .interpolationMethod(.monotone)
            }
            .chartXAxisLabel("step")
            .chartYAxisLabel("loss")
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }
}
