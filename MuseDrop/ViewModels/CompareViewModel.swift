//
//  CompareViewModel.swift
//  MuseDrop
//
//  Drives the Compare arena: holds the prompt + selected model profiles, fans
//  the prompt across them on concurrent streams, and republishes each column's
//  text/status/timing on the main actor.
//

import Foundation

@MainActor
final class CompareViewModel: ObservableObject {
    @Published var systemPrompt: String = ""
    @Published var userPrompt: String = ""
    @Published private(set) var profiles: [ModelProfile]
    @Published private(set) var columns: [ArenaColumn] = []
    @Published private(set) var isRunning = false
    @Published private(set) var savedPrompts: [SavedPrompt]
    /// Models found on host-native servers (Ollama / LM Studio / llama.cpp).
    @Published private(set) var localModels: [ModelProfile] = []
    /// OpenRouter's live catalog (for the model browser + cost meter).
    @Published private(set) var catalog: [CatalogModel] = []
    private var pricingByID: [String: CatalogModel] = [:]

    private var tasks: [Task<Void, Never>] = []

    init() {
        profiles = ModelProfile.loadSelected()
        savedPrompts = SavedPrompt.load()
        refreshLocalModels()
        loadCatalog()
    }

    func refreshLocalModels() {
        Task { @MainActor [weak self] in
            self?.localModels = await LocalInferenceService.shared.detectModels()
        }
    }

    func loadCatalog() {
        Task { @MainActor [weak self] in
            let models = await ModelCatalogService.shared.fetch()
            self?.catalog = models
            self?.pricingByID = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Estimated USD cost for a column (real per-token prices × estimated tokens).
    /// nil for free / local / on-device / unknown models.
    func estimatedCost(for column: ArenaColumn) -> Double? {
        guard let model = pricingByID[column.profile.modelId], !model.isFree else { return nil }
        return Double(column.promptTokens) * model.promptPrice
            + Double(column.estimatedTokens) * model.completionPrice
    }

    /// Summed estimated cost across every priceable column in the current run.
    /// nil when none has a known price (all local / free / on-device).
    var totalEstimatedCost: Double? {
        let costs = columns.compactMap { estimatedCost(for: $0) }
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    // MARK: - Saved prompt sets

    /// A sensible default name for the current prompt (its leading text), shown
    /// pre-filled in the save dialog.
    var suggestedPromptName: String {
        let user = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(user.prefix(48)) + (user.count > 48 ? "…" : "")
    }

    /// Save the current prompt + system + model line-up as a named set. A blank
    /// name falls back to the prompt's leading text; saving an existing name
    /// overwrites that set (named slots).
    func saveCurrentPrompt(name: String? = nil) {
        let user = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? suggestedPromptName : trimmed
        let set = SavedPrompt(name: finalName, system: systemPrompt, user: userPrompt, models: profiles)
        // Overwrite a set of the same name; newest first; cap the list.
        savedPrompts.removeAll { $0.name.caseInsensitiveCompare(finalName) == .orderedSame }
        savedPrompts.insert(set, at: 0)
        if savedPrompts.count > 20 { savedPrompts = Array(savedPrompts.prefix(20)) }
        SavedPrompt.save(savedPrompts)
    }

    /// Restore a saved set: its prompt, system prompt, and (when the set carries
    /// them) its model line-up.
    func loadPrompt(_ prompt: SavedPrompt) {
        systemPrompt = prompt.system
        userPrompt = prompt.user
        guard !prompt.models.isEmpty else { return }
        profiles = prompt.models
        ModelProfile.saveSelected(profiles)
    }

    func deletePrompt(_ id: UUID) {
        savedPrompts.removeAll { $0.id == id }
        SavedPrompt.save(savedPrompts)
    }

    var canRun: Bool {
        !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !profiles.isEmpty && !isRunning
    }

    // MARK: - Profiles

    func addProfile(_ profile: ModelProfile) {
        guard !profiles.contains(where: { $0.sameModel(as: profile) }) else { return }
        // Preserve baseURL — local servers need their endpoint to run.
        profiles.append(ModelProfile(label: profile.label, preset: profile.preset,
                                     modelId: profile.modelId, baseURL: profile.baseURL))
        ModelProfile.saveSelected(profiles)
    }

    func removeProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        ModelProfile.saveSelected(profiles)
    }


    // MARK: - Run

    func run() {
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !profiles.isEmpty, !isRunning else { return }

        stop()
        isRunning = true

        var messages: [LLMMessage] = []
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty { messages.append(LLMMessage(.system, system)) }
        messages.append(LLMMessage(.user, prompt))

        let promptTokens = max(0, Int((Double(system.count + prompt.count) / 4.0).rounded()))
        columns = profiles.map { var column = ArenaColumn(profile: $0); column.promptTokens = promptTokens; return column }
        for column in columns {
            let profile = column.profile
            let columnID = column.id
            let payload = messages
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                let start = Date()
                do {
                    let stream = await ArenaService.shared.stream(profile, messages: payload)
                    for try await delta in stream {
                        guard let index = self.columns.firstIndex(where: { $0.id == columnID }) else { return }
                        self.columns[index].text += delta
                        self.columns[index].elapsed = Date().timeIntervalSince(start)
                    }
                    self.finish(columnID, start: start, error: nil)
                } catch is CancellationError {
                    self.finish(columnID, start: start, error: nil, cancelled: true)
                } catch {
                    self.finish(columnID, start: start, error: error.localizedDescription)
                }
            }
            tasks.append(task)
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        for index in columns.indices where columns[index].status == .streaming {
            columns[index].status = .cancelled
        }
        isRunning = false
    }

    private func finish(_ columnID: UUID, start: Date, error: String?, cancelled: Bool = false) {
        if let index = columns.firstIndex(where: { $0.id == columnID }) {
            columns[index].elapsed = Date().timeIntervalSince(start)
            columns[index].error = error
            columns[index].status = cancelled ? .cancelled : (error == nil ? .done : .failed)
        }
        if columns.allSatisfy({ $0.status != .streaming }) {
            isRunning = false
        }
    }
}

struct ArenaColumn: Identifiable {
    let id = UUID()
    let profile: ModelProfile
    var text: String = ""
    var status: Status = .streaming
    var elapsed: TimeInterval = 0
    var error: String?
    /// Estimated prompt tokens (shared across columns) — for cost estimates.
    var promptTokens: Int = 0

    enum Status { case streaming, done, failed, cancelled }

    /// Rough token estimate (~4 chars/token) — exact counts need per-model usage.
    var estimatedTokens: Int { max(0, Int((Double(text.count) / 4.0).rounded())) }

    /// Estimated throughput, once enough time has elapsed to be meaningful.
    var tokensPerSecond: Double? {
        guard elapsed > 0.2, estimatedTokens > 0 else { return nil }
        return Double(estimatedTokens) / elapsed
    }
}

struct SavedPrompt: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var system: String
    var user: String
    /// The model line-up captured with this set, restored on load. Empty for
    /// older saves (made before sets carried models) — loading one of those
    /// leaves the current model selection untouched.
    var models: [ModelProfile] = []

    init(id: UUID = UUID(), name: String, system: String, user: String, models: [ModelProfile] = []) {
        self.id = id
        self.name = name
        self.system = system
        self.user = user
        self.models = models
    }

    // Resilient decode: prompt sets saved before `models` existed have no such
    // key, so decode it as empty rather than failing the whole list.
    private enum CodingKeys: String, CodingKey { case id, name, system, user, models }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        system = try c.decodeIfPresent(String.self, forKey: .system) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        models = try c.decodeIfPresent([ModelProfile].self, forKey: .models) ?? []
    }

    private static let key = "compare.savedPrompts"

    static func load() -> [SavedPrompt] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedPrompt].self, from: data) else { return [] }
        return decoded
    }

    static func save(_ prompts: [SavedPrompt]) {
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
