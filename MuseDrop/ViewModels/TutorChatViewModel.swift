//
//  TutorChatViewModel.swift
//  MuseDrop
//

import Foundation
import Combine

@MainActor
final class TutorChatViewModel: ObservableObject {
    @Published var messages: [TutorMessage] = []
    @Published var input: String = ""
    @Published var isStreaming = false
    @Published var isPreparing = true
    @Published var hasContext = false
    @Published var errorMessage: String?
    @Published private(set) var statusLine: String = ""

    let item: DownloadItem
    private var settings = LLMProviderSettings.load()
    private var streamTask: Task<Void, Never>?
    private let logService = LogService.shared

    init(item: DownloadItem) {
        self.item = item
        statusLine = LLMRouter.shared.statusDescription(settings: settings)
    }

    var providerConfigured: Bool {
        LLMRouter.shared.resolveRoute(settings: settings) != .unavailable
    }

    // MARK: - Provider / model switching

    /// Friendly label for the *effective* route (what actually runs this turn).
    var activeRouteLabel: String {
        switch LLMRouter.shared.resolveRoute(settings: settings) {
        case .onDevice:        return "Apple Intelligence"
        case .cloud(let model): return Self.friendlyName(for: model)
        case .unavailable:     return "Not configured"
        }
    }

    var onDeviceAvailable: Bool { LLMRouter.shared.isOnDeviceAvailable }

    /// Suggested cloud models the user can switch to from the tutor.
    var cloudModelOptions: [(label: String, id: String)] { LLMModelPreset.openRouterSuggestions }

    /// True when a cloud model is selected but no API key is configured, so the
    /// route is silently falling back (or unavailable).
    var needsKey: Bool {
        guard settings.preset != .onDevice, !settings.preferOnDevice else { return false }
        return !LLMRouter.shared.hasCloudKey
    }

    var isOnDeviceSelected: Bool { settings.preset == .onDevice }

    func isCloudModelSelected(_ id: String) -> Bool {
        settings.preset != .onDevice && settings.modelId == id
    }

    func selectOnDevice() {
        settings.preset = .onDevice
        settings.preferOnDevice = true
        persistSettings()
    }

    func selectCloudModel(_ id: String) {
        // Keep an existing custom endpoint; only convert away from on-device.
        if settings.preset == .onDevice { settings.preset = .openRouter }
        settings.modelId = id
        settings.preferOnDevice = false
        persistSettings()
    }

    private func persistSettings() {
        settings.save()
        statusLine = LLMRouter.shared.statusDescription(settings: settings)
        objectWillChange.send()
    }

    static func friendlyName(for modelId: String) -> String {
        if let match = LLMModelPreset.openRouterSuggestions.first(where: { $0.id == modelId }) {
            return match.label
        }
        // Fall back to the model name without its provider prefix.
        return modelId.split(separator: "/").last.map(String.init) ?? modelId
    }

    func onAppear() {
        settings = LLMProviderSettings.load()
        statusLine = LLMRouter.shared.statusDescription(settings: settings)

        Task {
            // Load saved conversation.
            messages = await DataStore.shared.tutorPersistence.conversation(for: item.id).messages
            // Prepare context + RAG index in the background.
            isPreparing = true
            hasContext = await TutorChatService.shared.prepare(item: item)
            isPreparing = false
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        errorMessage = nil
        settings = LLMProviderSettings.load()

        let userMessage = TutorMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(userMessage)

        let assistant = TutorMessage(role: .assistant, content: "")
        messages.append(assistant)
        persist(assistant)
        isStreaming = true

        let history = Array(messages.dropLast(2))   // exclude the just-added pair
        let item = self.item
        let settings = self.settings
        // Scale retrieval to the active provider's context window.
        let budget = RAGBudget.forRoute(LLMRouter.shared.resolveRoute(settings: settings))

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let llmMessages = await TutorChatService.shared.buildMessages(
                    item: item, history: history, userInput: text, useRAG: settings.enableRAG, budget: budget
                )
                let stream = await LLMRouter.shared.stream(messages: llmMessages, settings: settings)
                var accumulated = ""
                var lastFlush = Date.distantPast
                for try await delta in stream {
                    accumulated += delta
                    // Coalesce bursts of tokens into ~20 UI updates/sec so the
                    // main thread isn't re-rendered per tiny token (smoother).
                    if Date().timeIntervalSince(lastFlush) >= 0.05 {
                        lastFlush = Date()
                        let snapshot = accumulated
                        await MainActor.run { self.updateAssistant(id: assistant.id, content: snapshot) }
                    }
                }
                await MainActor.run {
                    self.finalizeAssistant(id: assistant.id, content: accumulated)
                    self.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    self.failAssistant(id: assistant.id, error: error)
                    self.isStreaming = false
                }
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clearConversation() {
        stop()
        messages = []
        Task { await DataStore.shared.tutorPersistence.clear(downloadId: item.id) }
    }

    // MARK: - Helpers

    private func updateAssistant(id: UUID, content: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].content = content
    }

    private func finalizeAssistant(id: UUID, content: String) {
        let final = content.trimmingCharacters(in: .whitespacesAndNewlines)
        updateAssistant(id: id, content: final.isEmpty ? "(no response)" : final)
        let stored = final.isEmpty ? "(no response)" : final
        Task { await DataStore.shared.tutorPersistence.updateMessage(id: id, content: stored, downloadId: item.id) }
    }

    private func failAssistant(id: UUID, error: Error) {
        if case LLMError.cancelled = error {
            // Keep whatever streamed so far; finalize it.
            if let idx = messages.firstIndex(where: { $0.id == id }) {
                finalizeAssistant(id: id, content: messages[idx].content)
            }
            return
        }
        let message = (error as? LLMError)?.errorDescription ?? error.localizedDescription
        errorMessage = message
        // Surface the error inline as the assistant bubble and persist it.
        finalizeAssistant(id: id, content: "⚠️ \(message)")
    }

    private func persist(_ message: TutorMessage) {
        let item = self.item
        Task { await DataStore.shared.tutorPersistence.append(message, downloadId: item.id, title: item.displayTitle) }
    }
}
