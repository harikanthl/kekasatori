//
//  WorkspaceStore.swift
//  MuseDrop
//
//  Persistence + selection for cockpit workspaces (Phase F). Local-first: stored
//  as JSON in (injectable) UserDefaults so it's unit-tested without disk/UI. The
//  Discover/DeepResearch/Notes "New workspace from…" entry points and run-history
//  wiring layer on top of this (F.2/F.3).
//

import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    /// App-wide store so the Cockpit UI and the run view models share selection,
    /// letting recorded runs link to the active workspace.
    static let shared = WorkspaceStore()

    @Published private(set) var workspaces: [Workspace]
    @Published var selectedID: UUID?

    private let defaults: UserDefaults
    private let clock: () -> Date
    private static let storageKey = "cockpit.workspaces"

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.clock = clock
        self.workspaces = Self.load(from: defaults)
        self.selectedID = workspaces.first?.id
    }

    var selected: Workspace? {
        workspaces.first { $0.id == selectedID }
    }

    // MARK: Mutations

    @discardableResult
    func create(title: String, source: WorkspaceSource = .blank, contextRefs: [ContextRef] = []) -> Workspace {
        let workspace = Workspace(title: title, source: source, contextRefs: contextRefs, createdAt: clock())
        workspaces.append(workspace)
        selectedID = workspace.id
        persist()
        return workspace
    }

    func update(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        var updated = workspace
        updated.updatedAt = clock()
        workspaces[index] = updated
        persist()
    }

    func delete(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        if selectedID == id { selectedID = workspaces.first?.id }
        persist()
    }

    func select(_ id: UUID) { selectedID = id }

    /// Attach a context pointer (deduped) to a workspace.
    func addContext(_ ref: ContextRef, to id: UUID) {
        mutate(id) { ws in
            guard !ws.contextRefs.contains(ref) else { return }
            ws.contextRefs.append(ref)
        }
    }

    func removeContext(_ ref: ContextRef, from id: UUID) {
        mutate(id) { ws in ws.contextRefs.removeAll { $0 == ref } }
    }

    /// Record a run against a workspace's history (deduped).
    func recordRun(_ runID: UUID, in id: UUID) {
        mutate(id) { ws in
            guard !ws.runIDs.contains(runID) else { return }
            ws.runIDs.append(runID)
        }
    }

    // MARK: Helpers

    private func mutate(_ id: UUID, _ change: (inout Workspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        var ws = workspaces[index]
        change(&ws)
        ws.updatedAt = clock()
        workspaces[index] = ws
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspaces) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [Workspace] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Workspace].self, from: data) else {
            return []
        }
        return decoded
    }
}
