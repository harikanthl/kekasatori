//
//  DiscoverView.swift
//  MuseDrop
//
//  Discover pillar (Research Cockpit, Phase 1): a native front-end for the
//  abstract-only DeepResearchAgent. The user poses a research question; the
//  agent plans focused queries, fans them across the scholarly providers,
//  screens + ranks the hits, and synthesizes a cited literature review. Stages
//  stream into the UI and the run is cancellable.
//

import SwiftUI
import AppKit

struct DiscoverView: View {
    @StateObject private var model = DiscoverViewModel()
    @State private var paperWindowController: NSWindowController?
    @State private var detailPaper: PaperHit?

    var body: some View {
        ZStack {
            discoverContent

            // Paper detail takes over the whole pane (full-window, no scroll-cramp),
            // with a "Back to Discover" button instead of opening a separate sheet.
            if let paper = detailPaper {
                PaperDetailView(
                    hit: paper,
                    isImporting: model.importingPaperID == paper.id,
                    onSave: { model.addToLibrary(paper) },
                    onBack: { detailPaper = nil }
                )
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.hover, value: detailPaper?.id)
    }

    private var discoverContent: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.md) {
                // Title row: heading on the leading edge, view switcher trailing.
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    ScreenHeader(
                        title: "Discover",
                        subtitle: "Browse and search the literature — synthesis, trending, and browse-by-area.",
                        systemImage: "sparkle.magnifyingglass"
                    )

                    Picker("Mode", selection: $model.mode) {
                        ForEach(DiscoverMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                // Field scope bar — full width, scrolls when fields overflow.
                ScrollView(.horizontal, showsIndicators: false) {
                    FieldSwitcher(field: model.field) { model.selectField($0) }
                        .padding(.vertical, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .screenColumn()
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.lg)

            switch model.mode {
            case .ask:
                ScrollView {
                    askContent
                        .padding(.bottom, Theme.Spacing.xxl)
                }
            case .trending:
                trendingLayout
            }
        }
        .onChange(of: model.paperToOpen?.id) { _, id in
            guard id != nil, let item = model.paperToOpen else { return }
            PlayerWindowPresenter.open(for: item, controller: $paperWindowController)
            model.paperToOpen = nil
            detailPaper = nil   // leave the detail page once the reader opens
        }
        .alert(
            "Couldn’t add to Library",
            isPresented: Binding(
                get: { model.importError != nil },
                set: { if !$0 { model.importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.importError = nil }
        } message: {
            Text(model.importError ?? "")
        }
    }

    // MARK: - Ask mode

    @ViewBuilder
    private var askContent: some View {
        VStack(spacing: Theme.Spacing.section) {
            VStack(spacing: Theme.Spacing.sm) {
                queryBar
                ProviderToggleBar(model: model)
            }

            if let stage = model.stage, model.isRunning {
                VStack(spacing: Theme.Spacing.sm) {
                    PlayfulLoader(size: 160)
                    ProgressTimeline(current: stage)
                }
                .frame(maxWidth: .infinity)
            }

            if let error = model.errorMessage {
                errorCard(error)
            }

            if let query = model.browseQuery {
                BrowseResults(
                    query: query,
                    results: model.browseResults,
                    isLoading: model.browseLoading,
                    errorMessage: model.browseError,
                    importingPaperID: model.importingPaperID,
                    sort: model.browseSort,
                    range: model.browseRange,
                    canLoadMore: model.canLoadMoreBrowse,
                    onSelectSort: { model.selectBrowseSort($0) },
                    onSelectRange: { model.selectBrowseRange($0) },
                    onBack: { model.exitBrowse() },
                    onLoadMore: { model.loadMoreBrowse() },
                    onAddToLibrary: { model.addToLibrary($0) },
                    onOpen: { detailPaper = $0 }
                )
            } else if let report = model.report {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    BackButton(title: "Research areas") { model.clearReport() }
                    reportSection(report)
                }
            } else if !model.isRunning && model.errorMessage == nil {
                TaxonomyBrowser(areas: model.domains) { query in
                    model.browse(query)
                }
            }
        }
        .screenColumn()
    }

    // MARK: - Trending mode

    private var trendingLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            DomainSidebar(
                domains: model.domains,
                selected: model.trendingDomain,
                enabled: TrendingFeedService.tabSupportsDomain(model.trendingTab),
                onSelect: { model.selectTrendingDomain($0) }
            )
            .frame(width: 210)

            SectionRule(axis: .vertical)

            ScrollView {
                trendingFeed
                    .padding(Theme.Spacing.page)
                    .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .onAppear { model.loadTrendingIfNeeded() }
    }

    private var trendingFeed: some View {
        TrendingFeed(
            availableTabs: TrendingTab.tabs(for: model.field),
            tab: model.trendingTab,
            range: model.trendingRange,
            papers: model.trending,
            isLoading: model.trendingLoading,
            errorMessage: model.trendingError,
            importingPaperID: model.importingPaperID,
            onSelectTab: { model.selectTrendingTab($0) },
            onSelectRange: { model.selectTrendingRange($0) },
            onReload: { model.reloadTrending() },
            onAddToLibrary: { model.addToLibrary($0) },
            onOpen: { detailPaper = $0 }
        )
    }

    // MARK: - Query bar

    private var queryBar: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                TextField(
                    "Search papers — or ask a question, then Deep Research…",
                    text: $model.question,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit { model.search() }
                .disabled(model.isRunning)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm + 1)
            .floatingChrome(radius: Theme.Radius.md)

            Picker("Depth", selection: $model.depth) {
                ForEach(ResearchDepth.allCases) { depth in
                    Text(depth.title).tag(depth)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .controlSize(.large)
            .disabled(model.isRunning)
            .help(model.depth.subtitle)

            if model.isRunning {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
            } else {
                // Default action: a fast paper lookup (no LLM, no key needed).
                Button {
                    model.search()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .controlSize(.large)
                .disabled(model.question.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)

                // Opt-in: synthesize a cited answer across the literature (the
                // 5-phase agent; needs an AI provider key).
                Button {
                    model.run()
                } label: {
                    Label("Deep Research", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Reads and synthesizes a cited answer across the literature. Requires an AI provider key (Settings → AI Providers).")
                .disabled(model.question.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            }
        }
    }

    // MARK: - Report

    private func reportSection(_ report: DeepResearchReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                SectionHeader("Synthesis", systemImage: "doc.text")
                Spacer(minLength: 0)
                Button {
                    model.copyReport()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            MarkdownMessageView(text: report.summary)
                .textSelection(.enabled)
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

            if let critique = report.critique {
                critiqueCard(critique)
            }

            if !report.citations.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    SectionHeader("Sources", systemImage: "books.vertical")
                    if report.candidateCount > report.citations.count {
                        StatusPill(text: "\(report.citations.count) of \(report.candidateCount) screened",
                                   systemImage: "line.3.horizontal.decrease.circle", color: .secondary)
                    }
                    if report.readCount > 0 {
                        StatusPill(text: "\(report.readCount) read in full",
                                   systemImage: "book", color: Theme.success)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.copyBibTeX()
                    } label: {
                        Label("BibTeX", systemImage: "text.quote")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(report.citations.enumerated()), id: \.element.id) { index, hit in
                        CitationRow(
                            number: index + 1,
                            hit: hit,
                            excerpts: report.excerpts[index + 1] ?? [],
                            isImporting: model.importingPaperID == hit.id,
                            onAddToLibrary: { model.addToLibrary(hit) },
                            onOpen: { detailPaper = hit }
                        )
                    }
                }
            }

            if !report.queriesUsed.isEmpty {
                queriesFooter(report.queriesUsed)
            }
        }
    }

    private func queriesFooter(_ queries: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Searched")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowWrap(spacing: Theme.Spacing.xs) {
                ForEach(queries, id: \.self) { query in
                    StatusPill(text: query, systemImage: "magnifyingglass")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.sm)
    }

    /// A skeptical review of the synthesis (claims vs. sources). "No issues found."
    /// reads as a clean pass; anything else is shown as flags to weigh.
    private func critiqueCard(_ critique: String) -> some View {
        let clean = critique.trimmingCharacters(in: .whitespacesAndNewlines)
        let passed = clean.localizedCaseInsensitiveContains("no issues found")
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(passed ? "Critique — passed" : "Critique",
                  systemImage: passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(passed ? Theme.success : Theme.warning)
            MarkdownMessageView(text: clean)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill((passed ? Theme.success : Theme.warning).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder((passed ? Theme.success : Theme.warning).opacity(0.25))
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
                .font(.title3)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }
}

// MARK: - Progress timeline

private struct ProgressTimeline: View {
    let current: DeepResearchStage

    private let steps: [(stage: DeepResearchStage, label: String, icon: String)] = [
        (.planning, "Planning", "list.bullet.rectangle"),
        (.searching, "Searching", "magnifyingglass"),
        (.screening, "Screening", "line.3.horizontal.decrease.circle"),
        (.reading, "Reading", "book"),
        (.synthesizing, "Synthesizing", "doc.text"),
        (.critiquing, "Critiquing", "checkmark.shield"),
    ]

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                let state = state(for: step.stage)
                HStack(spacing: Theme.Spacing.sm) {
                    Group {
                        switch state {
                        case .done:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                        case .active:
                            ProgressView()
                                .controlSize(.small)
                        case .pending:
                            Image(systemName: step.icon)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 18, height: 18)

                    Text(step.label)
                        .font(.subheadline.weight(state == .active ? .semibold : .regular))
                        .foregroundStyle(state == .pending ? .secondary : .primary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .floatingChrome()
        .animation(Theme.Motion.spring, value: current)
    }

    private enum StepState { case done, active, pending }

    private func state(for stage: DeepResearchStage) -> StepState {
        guard let lhs = order(current), let rhs = order(stage) else { return .pending }
        if rhs < lhs { return .done }
        if rhs == lhs { return current == .done ? .done : .active }
        return .pending
    }

    private func order(_ stage: DeepResearchStage) -> Int? {
        switch stage {
        case .planning:     return 0
        case .searching:    return 1
        case .screening:    return 2
        case .reading:      return 3
        case .synthesizing: return 4
        case .critiquing:   return 5
        case .done:         return 6
        }
    }
}

// MARK: - Citation row

private struct CitationRow: View {
    let number: Int
    let hit: PaperHit
    var excerpts: [String] = []
    let isImporting: Bool
    let onAddToLibrary: () -> Void
    var onOpen: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Button(action: onOpen) {
                    Text(hit.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    if hit.isOpenAccess {
                        StatusPill(text: "Open Access", systemImage: "lock.open", color: Theme.success)
                    } else {
                        StatusPill(text: "May require access", systemImage: "lock", color: .secondary)
                    }
                    if let count = hit.citationCount {
                        StatusPill(text: "\(count) citations", systemImage: "quote.bubble")
                    }
                    ForEach(hit.sources, id: \.self) { source in
                        StatusPill(text: ScholarlyProviderID(rawValue: source)?.displayName ?? source)
                    }
                }

                if !excerpts.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            ForEach(Array(excerpts.enumerated()), id: \.offset) { _, quote in
                                Text("“\(quote)”")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Label("\(excerpts.count) quoted excerpt\(excerpts.count == 1 ? "" : "s")",
                              systemImage: "quote.opening")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            actions
        }
        .padding(Theme.Spacing.md)
        .cardSurface(radius: Theme.Radius.md)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            if hit.isOpenAccess {
                // Free full text — import into Library and read in-app.
                Button(action: onAddToLibrary) {
                    if isImporting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Adding…")
                        }
                    } else {
                        Label("Add to Library", systemImage: "plus.rectangle.on.folder")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .disabled(isImporting)
            }

            // Always offer the source page; for gated papers this is the only path.
            if let link = hit.externalURLString, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(hit.isOpenAccess ? "Source page" : "Open page",
                          systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .frame(minWidth: 130, alignment: .trailing)
    }

    private var metaLine: String {
        let authors = hit.authors.prefix(3).joined(separator: ", ")
        let more = hit.authors.count > 3 ? " et al." : ""
        return [authors.isEmpty ? nil : authors + more,
                hit.year.map(String.init),
                hit.venue]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Field switcher

/// A sliding-pill toggle for the research field — softer and more tactile than
/// a plain segmented control. The selected segment is a filled accent capsule
/// that animates between options.
private struct FieldSwitcher: View {
    let field: ResearchField
    let onSelect: (ResearchField) -> Void
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ResearchField.allCases) { item in
                let isOn = item == field
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.caption.weight(.semibold))
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 6)
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .background {
                        if isOn {
                            Capsule(style: .continuous)
                                .fill(Theme.accent)
                                .matchedGeometryEffect(id: "fieldPill", in: pill)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.14)))
        .animation(Theme.Motion.spring, value: field)
    }
}

// MARK: - Provider toggle bar

/// Compact source selector: which free scholarly backends to query. About
/// discipline coverage + speed (arXiv adds a polite 3s spacing), not paywalls.
private struct ProviderToggleBar: View {
    @ObservedObject var model: DiscoverViewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.field.providers, id: \.self) { id in
                let on = model.isEnabled(id)
                Button {
                    model.toggleProvider(id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? Theme.accent : .secondary)
                        Text(id.displayName)
                            .foregroundStyle(on ? .primary : .secondary)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        (on ? Theme.accent.opacity(0.10) : Color.secondary.opacity(0.08)),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isRunning)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Domain sidebar

private struct DomainSidebar: View {
    let domains: [ResearchArea]
    let selected: ResearchArea?
    let enabled: Bool
    let onSelect: (ResearchArea?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Domains")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xs)

            DomainRow(symbol: "square.grid.3x3", name: "All domains",
                      isSelected: selected == nil) { onSelect(nil) }
            ForEach(domains) { area in
                DomainRow(symbol: area.symbol, name: area.name,
                          isSelected: selected?.id == area.id) { onSelect(area) }
            }

            Spacer(minLength: 0)

            if !enabled {
                Text("Domain filtering applies to Newest and Most Cited.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(enabled ? 1 : 0.5)
        .allowsHitTesting(enabled)
    }
}

private struct DomainRow: View {
    let symbol: String
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Theme.gold : .secondary)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(isSelected ? Theme.gold.opacity(0.12)
                          : (hovering ? Color.secondary.opacity(0.08) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

// MARK: - Trending feed

private struct TrendingFeed: View {
    let availableTabs: [TrendingTab]
    let tab: TrendingTab
    let range: TrendingTimeRange
    let papers: [PaperHit]
    let isLoading: Bool
    let errorMessage: String?
    let importingPaperID: String?
    let onSelectTab: (TrendingTab) -> Void
    let onSelectRange: (TrendingTimeRange) -> Void
    let onReload: () -> Void
    let onAddToLibrary: (PaperHit) -> Void
    let onOpen: (PaperHit) -> Void

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360),
                                    spacing: Theme.Spacing.md)]

    private var sourceNote: String {
        switch tab {
        case .trending:  return "Community-curated arXiv papers from HuggingFace, refreshed daily."
        case .newest:    return "Latest submissions across the core ML categories on arXiv."
        case .mostCited: return "Most-cited machine-learning works, ranked by OpenAlex."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text(sourceNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.md)
                Button(action: onReload) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isLoading)
            }

            // Lens + time-range controls.
            HStack(spacing: Theme.Spacing.md) {
                Picker("Lens", selection: Binding(get: { tab }, set: onSelectTab)) {
                    ForEach(availableTabs) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                if tab.supportedRanges.count > 1 {
                    Picker("Range", selection: Binding(get: { range }, set: onSelectRange)) {
                        ForEach(tab.supportedRanges) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }

            if isLoading && papers.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    PlayfulLoader(size: 220)
                    Text("Loading trending papers…").font(.callout).foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else if let errorMessage, papers.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    EmptyStateView(
                        systemImage: "wifi.exclamationmark",
                        title: "Couldn’t load trending",
                        message: errorMessage
                    )
                    Button("Try Again", action: onReload)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(papers) { hit in
                        TrendingCard(
                            hit: hit,
                            isImporting: importingPaperID == hit.id,
                            onAddToLibrary: { onAddToLibrary(hit) },
                            onOpen: { onOpen(hit) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrendingCard: View {
    let hit: PaperHit
    let isImporting: Bool
    let onAddToLibrary: () -> Void
    var onOpen: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            thumbnail

            Text(hit.title)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !hit.authors.isEmpty {
                Text(authorLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !hit.abstract.isEmpty {
                Text(hit.abstract)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metrics

            Spacer(minLength: 0)

            actions
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(DiscoverPalette.gold.opacity(hovering ? 0.45 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(DiscoverPalette.gold.opacity(0.08))
            if let thumb = hit.displayThumbnailURL, let url = URL(string: thumb) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().controlSize(.small)
                    case .failure:
                        placeholderGlyph
                    @unknown default:
                        placeholderGlyph
                    }
                }
            } else {
                placeholderGlyph
            }
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    private var placeholderGlyph: some View {
        // Fill the thumbnail box and crop overflow, without letting the square
        // art's intrinsic size drive the ZStack's layout.
        Color.clear
            .overlay {
                Image("ThumbAI")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .allowsHitTesting(false)
    }

    private var metrics: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let upvotes = hit.upvotes {
                StatusPill(text: "\(upvotes)", systemImage: "arrow.up", color: Theme.accent)
            }
            if let citations = hit.citationCount {
                StatusPill(text: "\(citations.formatted(.number.grouping(.automatic)))",
                           systemImage: "quote.bubble", color: .secondary)
            }
            if let stars = hit.stars {
                StatusPill(text: "\(stars.formatted(.number.grouping(.automatic)))",
                           systemImage: "star.fill", color: DiscoverPalette.gold)
            }
            if hit.isOpenAccess {
                StatusPill(text: "Open Access", systemImage: "lock.open", color: Theme.success)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if hit.isOpenAccess {
                Button(action: onAddToLibrary) {
                    if isImporting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Adding…")
                        }
                    } else {
                        Label("Add to Library", systemImage: "plus.rectangle.on.folder")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .disabled(isImporting)
            } else if let link = hit.externalURLString, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open page", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let repo = hit.repoURL, let url = URL(string: repo) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open code repository")
            }

            // OA cards already lead with Add to Library; offer the page too.
            // Gated cards handled their page link above.
            if hit.isOpenAccess, let link = hit.externalURLString, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open source page")
            }

            // Cockpit entry point: spin up a workspace for this paper/repo.
            Button {
                CockpitLauncher.newWorkspace(from: hit)
            } label: {
                Image(systemName: "gauge.with.dots.needle.67percent")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("New cockpit workspace from this paper")
        }
    }

    private var authorLine: String {
        let names = hit.authors.prefix(3).joined(separator: ", ")
        return hit.authors.count > 3 ? names + " et al." : names
    }
}

// MARK: - Browse results (taxonomy task → cards)

private struct BackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

private struct BrowseResults: View {
    let query: String
    let results: [PaperHit]
    let isLoading: Bool
    let errorMessage: String?
    let importingPaperID: String?
    let sort: PaperSort
    let range: TrendingTimeRange
    let canLoadMore: Bool
    let onSelectSort: (PaperSort) -> Void
    let onSelectRange: (TrendingTimeRange) -> Void
    let onBack: () -> Void
    let onLoadMore: () -> Void
    let onAddToLibrary: (PaperHit) -> Void
    let onOpen: (PaperHit) -> Void

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360),
                                    spacing: Theme.Spacing.md)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            BackButton(title: "Research areas", action: onBack)

            HStack(alignment: .firstTextBaseline) {
                Text("Papers on “\(query)”")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: Theme.Spacing.md)
                if !results.isEmpty {
                    Text("\(results.count) results")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Lens + time-range filters (mirrors the Trending controls).
            HStack(spacing: Theme.Spacing.md) {
                Picker("Sort", selection: Binding(get: { sort }, set: onSelectSort)) {
                    ForEach(PaperSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                Picker("Range", selection: Binding(get: { range }, set: onSelectRange)) {
                    ForEach(TrendingTimeRange.browseRanges) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
            }

            if isLoading && results.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    PlayfulLoader(size: 220)
                    Text("Searching…").font(.callout).foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else if let errorMessage, results.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass",
                               title: "No papers found",
                               message: errorMessage)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(results) { hit in
                        TrendingCard(
                            hit: hit,
                            isImporting: importingPaperID == hit.id,
                            onAddToLibrary: { onAddToLibrary(hit) },
                            onOpen: { onOpen(hit) }
                        )
                    }
                }

                if canLoadMore && !results.isEmpty {
                    Button(action: onLoadMore) {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Load more", systemImage: "arrow.down.circle")
                        }
                    }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(isLoading)
                    .padding(.top, Theme.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Taxonomy browser

/// Editorial gold used for the taxonomy rules/accents (echoes Papers With Code).
/// Sourced from the shared design token so the look stays consistent app-wide.
private enum DiscoverPalette {
    static let gold = Theme.gold
}

private func paperCountLabel(_ count: Int?) -> String {
    guard let count else { return "" }
    return "\(count.formatted(.number.grouping(.automatic))) papers"
}

/// Browsable spine of research areas (bundled, no network), laid out like the
/// Papers With Code tasks page. Tapping a task seeds and runs a search.
private struct TaxonomyBrowser: View {
    let areas: [ResearchArea]
    let onPick: (String) -> Void

    private var totalTasks: Int { areas.reduce(0) { $0 + $1.tasks.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Browse research by area")
                    .font(.title3.weight(.semibold))
                Text("Click any task to run a cited literature synthesis — or type your own question above.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(areas) { area in
                AreaSection(area: area, onPick: onPick)
            }

            Text("\(totalTasks) tasks across \(areas.count) areas.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AreaSection: View {
    let area: ResearchArea
    let onPick: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360),
                                    spacing: Theme.Spacing.sm)]

    private var areaMeta: String {
        var parts = ["\(area.tasks.count) tasks"]
        if let count = area.paperCount {
            parts.append("\(count.formatted(.number.grouping(.automatic))) papers")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Image(systemName: area.symbol)
                    .font(.headline)
                    .foregroundStyle(DiscoverPalette.gold)
                Text(area.name)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: Theme.Spacing.md)
                Text(areaMeta)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Gold rule — the Papers With Code motif (shared design token).
            SectionRule()

            Text(area.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
                ForEach(area.tasks) { task in
                    TaskRow(task: task) { onPick(task.searchQuery) }
                }
            }
        }
    }
}

private struct TaskRow: View {
    let task: ResearchTask
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(task.name)
                    .font(.callout)
                    .foregroundStyle(hovering ? DiscoverPalette.gold : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Spacing.sm)
                if let count = task.paperCount {
                    Text(count.formatted(.number.grouping(.automatic)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(hovering ? DiscoverPalette.gold.opacity(0.10) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }
}

// MARK: - Simple flow layout (wrapping pills)

private struct FlowWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    DiscoverView()
        .frame(width: 900, height: 700)
}
