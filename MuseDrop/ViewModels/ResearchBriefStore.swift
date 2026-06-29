//
//  ResearchBriefStore.swift
//  MuseDrop
//
//  Persists DeepResearch reports as lightweight "briefs" so a transient research
//  run becomes durable context a cockpit Workspace can reference (via
//  `ContextRef.researchBrief`). Local-first JSON in UserDefaults, capped.
//

import Foundation

struct ResearchBrief: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
    }
}

@MainActor
final class ResearchBriefStore: ObservableObject {
    static let shared = ResearchBriefStore()

    @Published private(set) var briefs: [ResearchBrief]   // newest first

    private let defaults: UserDefaults
    private let limit: Int
    private static let storageKey = "cockpit.researchBriefs"

    init(defaults: UserDefaults = .standard, limit: Int = 100) {
        self.defaults = defaults
        self.limit = limit
        self.briefs = Self.load(from: defaults)
    }

    /// The most recent brief (e.g. the research the user just ran).
    var latest: ResearchBrief? { briefs.first }

    func brief(_ id: UUID) -> ResearchBrief? { briefs.first { $0.id == id } }

    @discardableResult
    func add(title: String, text: String) -> ResearchBrief {
        let brief = ResearchBrief(title: title, text: text)
        briefs.insert(brief, at: 0)
        if briefs.count > limit { briefs.removeLast(briefs.count - limit) }
        persist()
        return brief
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(briefs) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [ResearchBrief] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ResearchBrief].self, from: data) else {
            return []
        }
        return decoded
    }
}
