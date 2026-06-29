//
//  RunHistoryStore.swift
//  MuseDrop
//
//  A persisted trail of completed runs (Phase F.2). Every CodeBox / Run-pillar
//  execution folds its `RunEvent` stream into a `Run` (via `Run.apply`) and lands
//  here on finish, so the cockpit has a queryable history — the substrate the
//  Workspace run list, the agent operator, and the memory backbone all read.
//  Local-first: JSON in (injectable) UserDefaults, capped to the most recent N.
//

import Foundation

@MainActor
final class RunHistoryStore: ObservableObject {
    static let shared = RunHistoryStore()

    @Published private(set) var runs: [Run]   // most-recent first

    private let defaults: UserDefaults
    private let limit: Int
    private static let storageKey = "cockpit.runHistory"

    init(defaults: UserDefaults = .standard, limit: Int = 200) {
        self.defaults = defaults
        self.limit = limit
        self.runs = Self.load(from: defaults)
    }

    /// Insert or replace a run (by id), newest first, capped to `limit`.
    func record(_ run: Run) {
        runs.removeAll { $0.id == run.id }
        runs.insert(run, at: 0)
        if runs.count > limit { runs.removeLast(runs.count - limit) }
        persist()
    }

    func recent(_ count: Int) -> [Run] {
        Array(runs.prefix(count))
    }

    func forWorkspace(_ workspaceID: UUID) -> [Run] {
        runs.filter { $0.workspaceID == workspaceID }
    }

    func clear() {
        runs.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(runs) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [Run] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Run].self, from: data) else {
            return []
        }
        return decoded
    }
}
