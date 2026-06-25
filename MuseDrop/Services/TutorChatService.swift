//
//  TutorChatService.swift
//  MuseDrop
//
//  Assembles tutor context from the current item (paper text / transcript),
//  indexes it for RAG, and builds the LLM message list for each turn.
//

import Foundation

actor TutorChatService {
    static let shared = TutorChatService()

    /// Cached raw source text per item (fallback when RAG is off / empty).
    private var sourceCache: [UUID: String] = [:]
    private let maxHistoryTurns = 8

    private init() {}

    /// Load the item's source text and index it for retrieval. Idempotent.
    /// Returns true if any usable context exists.
    @discardableResult
    func prepare(item: DownloadItem) async -> Bool {
        let text = await loadSourceText(for: item)
        sourceCache[item.id] = text
        if text.count > 200 {
            await RAGIndexService.shared.ingest(downloadId: item.id, text: text)
        }
        return text.count > 200
    }

    var hasNoSourcePlaceholder: Bool { false }

    /// Build the message list for one turn.
    func buildMessages(
        item: DownloadItem,
        history: [TutorMessage],
        userInput: String,
        useRAG: Bool,
        budget: RAGBudget = .onDevice
    ) async -> [LLMMessage] {
        var messages: [LLMMessage] = []
        messages.append(LLMMessage(.system, systemPrompt(for: item)))

        let contextBlock = await contextBlock(for: item, query: userInput, useRAG: useRAG, budget: budget)
        if !contextBlock.isEmpty {
            messages.append(LLMMessage(.system, contextBlock))
        }

        // Recent history (trim to last N turns).
        let recent = history.suffix(maxHistoryTurns * 2)
        for msg in recent where msg.role != .system {
            messages.append(LLMMessage(msg.role, msg.content))
        }

        messages.append(LLMMessage(.user, userInput))
        return messages
    }

    // MARK: - Context

    private func systemPrompt(for item: DownloadItem) -> String {
        """
        You are MuseDrop's study tutor. Help the user understand "\(item.displayTitle)".
        Ground answers in the provided source excerpts. If the excerpts don't cover the \
        question, say so briefly and answer from general knowledge, clearly flagged. \
        Be concise, use plain language, and show worked steps for technical/math content. \
        Do not invent citations or quote text that isn't in the excerpts.
        """
    }

    private func contextBlock(for item: DownloadItem, query: String, useRAG: Bool, budget: RAGBudget) async -> String {
        if useRAG {
            let chunks = await RAGIndexService.shared.retrieve(downloadId: item.id, query: query, limit: budget.chunkLimit)
            if !chunks.isEmpty {
                let joined = chunks.enumerated()
                    .map { "[\($0.offset + 1)] \($0.element.text)" }
                    .joined(separator: "\n\n")
                return "Relevant excerpts from the source:\n\n\(joined)"
            }
        }
        // Fallback: truncated full text.
        let text = sourceCache[item.id] ?? ""
        guard !text.isEmpty else { return "" }
        let clamped = text.count > budget.fallbackChars ? String(text.prefix(budget.fallbackChars)) + "…" : text
        return "Source material:\n\n\(clamped)"
    }

    private func loadSourceText(for item: DownloadItem) async -> String {
        if let cached = sourceCache[item.id] { return cached }

        if item.isResearchDocument, let bundle = item.paperBundleURL {
            let text = PDFTextExtractor.extractText(bundleURL: bundle)
            if !text.isEmpty { return text }
        }

        if let transcript = await MediaAIService.shared.loadSavedTranscript(for: item) {
            return transcript.text
        }
        return ""
    }
}
