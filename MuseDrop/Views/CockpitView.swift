//
//  CockpitView.swift
//  MuseDrop
//
//  Phase F.3: the cockpit home — workspaces + their run history made visible.
//  A workspace is the active research task; runs from the Code box / Run pillar
//  record against the selected workspace (see RunHistoryStore / WorkspaceStore).
//  "New workspace from a repo" is the DeepSpec-style entry point; Discover wires a
//  "from this paper" button into the same `create(...)`.
//

import SwiftUI

extension Notification.Name {
    /// Posted when a workspace is created from elsewhere (Discover) so the shell
    /// can switch to the Cockpit tab.
    static let openCockpit = Notification.Name("openCockpit")
    /// Posted from the Cockpit to jump into the Code / Notebox workbench with the
    /// active workspace still selected (so runs land in it).
    static let openCode = Notification.Name("openCode")
    static let openNotebox = Notification.Name("openNotebox")
}

/// Shared entry point for "start a workspace from this paper", used by the Discover
/// card and the paper viewer. Attaches the paper + the most recent DeepResearch
/// brief as context, then asks the shell to switch to the Cockpit.
@MainActor
enum CockpitLauncher {
    static func newWorkspace(from hit: PaperHit) {
        var refs: [ContextRef] = [.paper(hit.id)]
        if let brief = ResearchBriefStore.shared.latest {
            refs.append(.researchBrief(brief.id))
        }
        let source: WorkspaceSource = (hit.repoURL.flatMap { URL(string: $0) })
            .map { .repo(url: $0, ref: nil) } ?? .paper(paperID: hit.id)
        WorkspaceStore.shared.create(title: hit.title, source: source, contextRefs: refs)
        NotificationCenter.default.post(name: .openCockpit, object: nil)
    }
}

struct CockpitView: View {
    @ObservedObject private var workspaces = WorkspaceStore.shared
    @ObservedObject private var history = RunHistoryStore.shared
    @StateObject private var studyPacks = StudyPackHistoryViewModel()
    @State private var showNew = false
    @State private var workspaceToDelete: Workspace?

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
            detail
                .frame(minWidth: 380)
            AgentChatView(workspace: workspaces.selected, recentRuns: agentRuns)
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
        }
        .onAppear { studyPacks.reload() }
        .sheet(isPresented: $showNew) { NewWorkspaceSheet(store: workspaces) }
        .confirmationDialog(
            "Delete “\(workspaceToDelete?.title ?? "")”?",
            isPresented: Binding(get: { workspaceToDelete != nil },
                                 set: { if !$0 { workspaceToDelete = nil } }),
            presenting: workspaceToDelete
        ) { ws in
            Button("Delete Workspace", role: .destructive) {
                workspaces.delete(ws.id); workspaceToDelete = nil
            }
            Button("Cancel", role: .cancel) { workspaceToDelete = nil }
        } message: { _ in
            Text("This removes the workspace and its run links. The runs themselves stay in history.")
        }
    }

    /// Runs the agent is grounded on: the selected workspace's, or recent global.
    private var agentRuns: [Run] {
        if let ws = workspaces.selected { return history.forWorkspace(ws.id) }
        return history.recent(10)
    }

    /// Jump into a workbench with this workspace active — runs there land in this
    /// workspace's history (and memory), and use the compute target set above.
    private var workbenchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                NotificationCenter.default.post(name: .openCode, object: nil)
            } label: {
                Label("Open in Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)

            Button {
                NotificationCenter.default.post(name: .openNotebox, object: nil)
            } label: {
                Label("Notebox", systemImage: "book.pages")
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Workspaces").font(.headline)
                Spacer()
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New workspace")
            }
            .padding(Theme.Spacing.md)
            SectionRule()

            if workspaces.workspaces.isEmpty {
                EmptyStateView(systemImage: "square.grid.2x2",
                               title: "No workspaces yet",
                               message: "Create one to group a repo, its runs, and its notes.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { workspaces.selectedID },
                                        set: { if let id = $0 { workspaces.select(id) } })) {
                    ForEach(workspaces.workspaces) { ws in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ws.title).font(.callout.weight(.medium)).lineLimit(1)
                            Text("\(ws.source.label) · \(ws.runIDs.count) run\(ws.runIDs.count == 1 ? "" : "s")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .tag(ws.id)
                        .contextMenu {
                            Button("Delete…", role: .destructive) { workspaceToDelete = ws }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { workspaceToDelete = ws } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                // Delete key on the selected row (with the same confirmation).
                .onDeleteCommand { if let ws = workspaces.selected { workspaceToDelete = ws } }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let ws = workspaces.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ws.title).font(.title2.weight(.semibold))
                            Spacer(minLength: Theme.Spacing.md)
                            // The compute dial — settable right from the Cockpit.
                            ComputePill(store: ComputeTargetStore.shared)
                        }
                        Text(sourceSubtitle(ws.source))
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        workbenchBar
                        contextSection(for: ws)
                        briefDisclosures(for: ws)
                    }
                    .padding(.top, Theme.Spacing.xl)

                    SectionRule()

                    runHistorySection(runs: history.forWorkspace(ws.id))
                }
                .screenColumn()
                .padding(.bottom, Theme.Spacing.xxl)
            }
        } else {
            VStack(spacing: Theme.Spacing.lg) {
                EmptyStateView(systemImage: "gauge.with.dots.needle.67percent",
                               title: "Pick or create a workspace",
                               message: "Recent runs across all tasks:")
                runHistorySection(runs: history.recent(30))
                    .screenColumn()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, Theme.Spacing.xxl)
        }
    }

    private func runHistorySection(runs: [Run]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Run history").font(.headline)
            if runs.isEmpty {
                Text("No runs yet. Runs from Code and Run land here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(runs) { run in RunHistoryRow(run: run) }
            }
        }
    }

    /// Context chips (with remove) + an "Attach note" picker over the user's
    /// study packs — manual because there's no reliable paper↔note auto-link.
    @ViewBuilder
    private func contextSection(for ws: Workspace) -> some View {
        let attachedNotes = Set(ws.contextRefs.compactMap { ref -> UUID? in
            if case .note(let id) = ref { return id } else { return nil }
        })
        let available = studyPacks.packs.filter { !attachedNotes.contains($0.downloadId) }

        ChipFlow(spacing: Theme.Spacing.sm) {
            ForEach(ws.contextRefs) { ref in
                Text(contextLabel(ref))
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            workspaces.removeContext(ref, from: ws.id)
                        }
                    }
            }

            Menu {
                if available.isEmpty {
                    Text("No study packs to attach")
                } else {
                    ForEach(available) { pack in
                        Button(pack.mediaTitle) {
                            workspaces.addContext(.note(pack.downloadId), to: ws.id)
                        }
                    }
                }
            } label: {
                Label("Attach note", systemImage: "paperclip")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    /// Render any attached DeepResearch briefs inline, so the context the agent
    /// will use is visible (and auto-attached briefs aren't just an opaque chip).
    @ViewBuilder
    private func briefDisclosures(for ws: Workspace) -> some View {
        let briefIDs: [UUID] = ws.contextRefs.compactMap {
            if case .researchBrief(let id) = $0 { return id } else { return nil }
        }
        ForEach(briefIDs, id: \.self) { id in
            if let brief = ResearchBriefStore.shared.brief(id) {
                DisclosureGroup {
                    Text(brief.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.xs)
                } label: {
                    Label("Research brief · \(brief.title)", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.medium))
                }
            }
        }
    }

    // MARK: Helpers

    private func sourceSubtitle(_ source: WorkspaceSource) -> String {
        switch source {
        case .blank:                  return "Blank workspace"
        case .paper(let id):          return "Paper · \(id)"
        case .repo(let url, let ref): return "Repo · \(url.absoluteString)\(ref.map { " @ \($0)" } ?? "")"
        case .notebook(let url):      return "Notebook · \(url.lastPathComponent)"
        }
    }

    private func contextLabel(_ ref: ContextRef) -> String {
        switch ref {
        case .paper:         return "paper"
        case .note(let id):
            let title = studyPacks.packs.first { $0.downloadId == id }?.mediaTitle
            return title.map { "note · \($0)" } ?? "note"
        case .transcript:    return "transcript"
        case .researchBrief: return "brief"
        }
    }
}

private struct RunHistoryRow: View {
    let run: Run

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(run.kind.rawValue.capitalized).font(.callout.weight(.medium))
                if let line = run.log.split(separator: "\n").last.map(String.init), !line.isEmpty {
                    Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let cost = ComputeCost.accrued(run.costUSD) {
                Text(cost).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Text(run.createdAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.sm)
        .cardSurface(radius: Theme.Radius.sm)
    }

    private var icon: String {
        switch run.status {
        case .succeeded: return "checkmark.circle.fill"
        case .failed:    return "xmark.octagon.fill"
        case .canceled:  return "stop.circle.fill"
        default:         return "circle.dotted"
        }
    }
    private var color: Color {
        switch run.status {
        case .succeeded: return Theme.success
        case .failed:    return .red
        case .canceled:  return .secondary
        default:         return Theme.accent
        }
    }
}

struct NewWorkspaceSheet: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable { case blank, repo; var id: String { rawValue }
        var label: String { self == .blank ? "Blank" : "From repo" } }

    @State private var kind: Kind = .blank
    @State private var title = ""
    @State private var repoURL = ""

    private var repo: URL? {
        let t = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: t), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
    private var canCreate: Bool {
        switch kind {
        case .blank: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .repo:  return repo != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workspace").font(.system(.headline, design: .serif))
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Title", text: $title, prompt: Text("Reproduce DeepSpec"))
                if kind == .repo {
                    TextField("Repo URL", text: $repoURL, prompt: Text("https://github.com/deepseek-ai/DeepSpec"))
                        .font(.callout.monospaced())
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(18)
        .frame(width: 460)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .blank:
            store.create(title: trimmed.isEmpty ? "Untitled" : trimmed)
        case .repo:
            guard let repo else { return }
            let name = trimmed.isEmpty ? repo.deletingPathExtension().lastPathComponent : trimmed
            store.create(title: name, source: .repo(url: repo, ref: nil))
        }
        dismiss()
    }
}
