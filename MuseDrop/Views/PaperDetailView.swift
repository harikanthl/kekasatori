//
//  PaperDetailView.swift
//  MuseDrop
//
//  Papers-with-Code-style detail page for a `PaperHit`. Opened when a paper is
//  clicked in Discover. Header + action toolbar (PDF / arXiv / Hugging Face /
//  Code / Save), an AI-generated TL;DR, the abstract, AI-derived Tasks & Methods
//  tags, a BibTeX citation card, and related papers. Everything beyond the raw
//  fields (TL;DR, tags, related) is fetched in `.task` and degrades to nothing
//  when unavailable, so the page always renders from `PaperHit` alone.
//

import SwiftUI
import AppKit

struct PaperDetailView: View {
    let hit: PaperHit
    /// True while this paper is being imported into the Library (drives the Save
    /// button's spinner). Owned by the presenting view model.
    var isImporting: Bool = false
    /// Add this paper to the Library (open-access only). Wired to the existing
    /// Discover import flow, which opens the reader window on success.
    var onSave: () -> Void = {}
    /// Return to the list this page was opened from. When set, the top bar shows
    /// a "Back to Discover" button; otherwise it falls back to `dismiss` (sheet).
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var tldr: String?
    @State private var loadingTLDR = true
    @State private var tasks: [CatalogTask] = []
    @State private var methods: [ResearchMethod] = []
    @State private var related: [PaperHit] = []
    @State private var loadingRelated = true
    @State private var abstractExpanded = false
    @State private var copiedCitation = false
    @State private var codeLinks: [PwCCodeLink] = []
    @State private var codeLoading = false

    private var bibtex: String { PaperDetailService.bibtex(for: hit) }
    private var showTLDR: Bool { loadingTLDR || tldr != nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    header
                    actionBar
                    if showTLDR { tldrCard }
                    abstractSection
                    if !tasks.isEmpty { tasksSection }
                    if !methods.isEmpty { methodsSection }
                    codeSection
                    citationSection
                    relatedSection
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, Theme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: hit.id) { await load() }
        .task(id: hit.id) { await loadCode() }
    }

    // MARK: - Code (Papers with Code)

    @ViewBuilder
    private var codeSection: some View {
        if codeLoading || !codeLinks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Code").font(.headline)
                    if !codeLinks.isEmpty {
                        Text("\(codeLinks.count)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if codeLoading { ProgressView().controlSize(.small) }
                    Spacer()
                }

                ForEach(codeLinks) { link in
                    Button {
                        if let url = URL(string: link.repoURL) { openURL(url) }
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(.secondary)
                            Text(link.displayName).font(.callout.weight(.medium)).lineLimit(1)
                            if link.isOfficial {
                                Text("official")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.accent.opacity(0.15)))
                                    .foregroundStyle(Theme.accent)
                            }
                            if let fw = link.frameworkLabel {
                                Text(fw)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7).padding(.horizontal, Theme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(Color.secondary.opacity(0.06)))
                }

                if !codeLinks.isEmpty {
                    Text("Code links via Papers with Code (CC-BY-SA).")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func loadCode() async {
        guard let arxiv = hit.arxivId, !arxiv.isEmpty else { codeLinks = []; return }
        codeLoading = true
        let links = await PwCIndexService.shared.codeLinks(arxivId: arxiv)
        codeLinks = links
        codeLoading = false
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button { onBack?() ?? dismiss() } label: {
                Label("Discover", systemImage: "chevron.left")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to Discover")
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(hit.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if !hit.authors.isEmpty {
                Text(authorLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ChipFlow(spacing: Theme.Spacing.xs) {
                ForEach(badges, id: \.self) { badge in
                    metaBadge(badge.icon, badge.text)
                }
            }
        }
    }

    private var authorLine: String {
        let cap = 12
        if hit.authors.count > cap {
            return hit.authors.prefix(cap).joined(separator: ", ") + ", et al."
        }
        return hit.authors.joined(separator: ", ")
    }

    private struct Badge: Hashable { let icon: String; let text: String }

    private var badges: [Badge] {
        var out: [Badge] = []
        if let arxivId = hit.arxivId, !arxivId.isEmpty {
            out.append(Badge(icon: "doc.plaintext", text: "arXiv:\(PaperHit.normalizedArxivId(arxivId))"))
        }
        if let venue = hit.venue, !venue.isEmpty, venue.lowercased() != "arxiv" {
            out.append(Badge(icon: "building.columns", text: venue))
        }
        if let year = hit.year {
            out.append(Badge(icon: "calendar", text: String(year)))
        }
        if let cites = hit.citationCount, cites > 0 {
            out.append(Badge(icon: "quote.bubble", text: "\(cites.formatted(.number.grouping(.automatic))) citations"))
        }
        if let stars = hit.stars, stars > 0 {
            out.append(Badge(icon: "star", text: stars.formatted(.number.grouping(.automatic))))
        }
        if let up = hit.upvotes, up > 0 {
            out.append(Badge(icon: "hand.thumbsup", text: String(up)))
        }
        return out
    }

    private func metaBadge(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.caption2)
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.10)))
    }

    // MARK: - Action toolbar

    private var actionBar: some View {
        ChipFlow(spacing: Theme.Spacing.sm) {
            // Finished reading? Jump straight into a cockpit workspace for it.
            actionButton("Start in Cockpit", "gauge.with.dots.needle.67percent", tint: Theme.accent) {
                CockpitLauncher.newWorkspace(from: hit)
            }
            if let pdf = PaperDetailService.pdfURL(for: hit) {
                actionButton("View PDF", "doc.richtext", tint: Theme.accent) { openURL(pdf) }
            }
            if let abs = PaperDetailService.abstractPageURL(for: hit) {
                actionButton("arXiv page", "safari", tint: nil) { openURL(abs) }
            }
            if let hf = PaperDetailService.huggingFaceURL(for: hit) {
                actionButton("Hugging Face", "face.smiling", tint: nil) { openURL(hf) }
            }
            if let repo = hit.repoURL, let url = URL(string: repo) {
                actionButton("Code", "chevron.left.forwardslash.chevron.right", tint: nil) { openURL(url) }
            }
            if hit.isOpenAccess {
                saveButton
            }
        }
    }

    private func actionButton(_ title: String, _ systemImage: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 7)
            .background(Capsule().fill((tint ?? .secondary).opacity(0.10)))
            .overlay(Capsule().strokeBorder((tint ?? .secondary).opacity(0.28)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            HStack(spacing: 6) {
                if isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus.circle")
                }
                Text(isImporting ? "Adding…" : "Save to Library")
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.accent.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isImporting)
    }

    // MARK: - TL;DR

    private var tldrCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("TL;DR · AI-generated", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.gold)

            if loadingTLDR {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Generating summary…").foregroundStyle(.secondary)
                }
                .font(.callout)
            } else if let tldr {
                Text(tldr)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.gold.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.gold.opacity(0.30)))
    }

    // MARK: - Abstract

    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Abstract", systemImage: "doc.text")
            Text(hit.abstract.isEmpty ? "No abstract available." : hit.abstract)
                .font(.callout)
                .foregroundStyle(hit.abstract.isEmpty ? .secondary : .primary)
                .lineLimit(abstractExpanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
            if hit.abstract.count > 420 {
                Button(abstractExpanded ? "Show less" : "Read full abstract") {
                    withAnimation(Theme.Motion.hover) { abstractExpanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    // MARK: - Tasks / Methods (canonical catalog tags)

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Tasks", systemImage: "target")
            ChipFlow(spacing: Theme.Spacing.xs) {
                ForEach(tasks) { task in
                    chip(task.name, tint: Theme.gold)
                        .help(task.area.rawValue)
                }
            }
        }
    }

    private var methodsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Methods", systemImage: "wrench.and.screwdriver")
            ChipFlow(spacing: Theme.Spacing.xs) {
                ForEach(methods) { method in
                    chip(method.label, tint: Theme.accent)
                        .help(method.area.rawValue)
                }
            }
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.25)))
    }

    // MARK: - Citation

    private var citationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                sectionHeader("Citation", systemImage: "quote.bubble")
                Spacer()
                Button { copyCitation() } label: {
                    Label(copiedCitation ? "Copied" : "Copy BibTeX",
                          systemImage: copiedCitation ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(copiedCitation ? Theme.success : Theme.accent)
            }
            Text(bibtex)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }

    private func copyCitation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
        withAnimation(Theme.Motion.hover) { copiedCitation = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation(Theme.Motion.hover) { copiedCitation = false } }
        }
    }

    // MARK: - Related

    @ViewBuilder
    private var relatedSection: some View {
        if loadingRelated {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Related papers", systemImage: "rectangle.stack")
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Finding related work…").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if !related.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeader("Related papers", systemImage: "rectangle.stack")
                VStack(spacing: 2) {
                    ForEach(related) { paper in
                        RelatedRow(hit: paper) {
                            if let url = PaperDetailService.abstractPageURL(for: paper) { openURL(url) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func load() async {
        // Tasks & Methods are deterministic catalog lookups — instant, offline.
        let corpus = hit.title + ". " + hit.abstract
        tasks = TasksCatalog.detect(in: corpus)
        methods = MethodsCatalog.detect(in: corpus)

        // TL;DR (LLM) and related papers (network) stream in after.
        loadingTLDR = true
        loadingRelated = true
        async let tldrTask = PaperDetailService.tldr(for: hit)
        async let relatedTask = PaperDetailService.related(to: hit)
        tldr = await tldrTask
        loadingTLDR = false
        related = await relatedTask
        loadingRelated = false
    }
}

// MARK: - Related row

private struct RelatedRow: View {
    let hit: PaperHit
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(hovering ? Theme.accent : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if !hit.authors.isEmpty {
                        Text(authorsShort).lineLimit(1)
                    }
                    if let year = hit.year { Text("· \(String(year))") }
                    if let cites = hit.citationCount, cites > 0 { Text("· \(cites) cites") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(hovering ? Color.secondary.opacity(0.07) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.hover, value: hovering)
    }

    private var authorsShort: String {
        if hit.authors.count > 3 {
            return hit.authors.prefix(3).joined(separator: ", ") + ", et al."
        }
        return hit.authors.joined(separator: ", ")
    }
}

// MARK: - Wrapping flow layout (chips / action buttons)

/// Shared wrapping flow layout used by chip/badge rows across the app
/// (paper detail, Run results, …).
struct ChipFlow: Layout {
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
