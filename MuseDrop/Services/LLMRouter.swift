//
//  LLMRouter.swift
//  MuseDrop
//
//  Routes tutor chat to the right backend based on BYOK settings:
//  on-device Apple Intelligence → OpenRouter/custom cloud → clear error.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

actor LLMRouter {
    static let shared = LLMRouter()

    private init() {}

    /// Whether on-device generation is usable on this Mac right now.
    nonisolated var isOnDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return FoundationModelBridge.isAvailable }
        #endif
        return false
    }

    /// Whether a cloud chat key is configured (the shared OpenRouter/custom key).
    nonisolated var hasCloudKey: Bool { KeychainService.has(KeychainService.Account.llmChat) }

    /// Whether a key exists for this preset's provider (preset-aware: HF uses its
    /// own token, OpenRouter/custom share `llmChat`).
    nonisolated func hasKey(for settings: LLMProviderSettings) -> Bool {
        guard let account = settings.preset.keychainAccount else { return false }
        return KeychainService.has(account)
    }

    /// Human-readable description of the active route, for UI.
    nonisolated func statusDescription(settings: LLMProviderSettings) -> String {
        switch resolveRoute(settings: settings) {
        case .onDevice: return "On-device · Apple Intelligence"
        case .cloud(let model): return "Cloud · \(model)"
        case .unavailable: return "No provider configured"
        }
    }

    enum Route: Equatable {
        case onDevice
        case cloud(model: String)
        case unavailable
    }

    nonisolated func resolveRoute(settings: LLMProviderSettings) -> Route {
        switch settings.preset {
        case .onDevice:
            return isOnDeviceAvailable ? .onDevice : .unavailable
        case .openRouter, .huggingFace, .runPod, .custom:
            if settings.preferOnDevice, isOnDeviceAvailable { return .onDevice }
            if hasKey(for: settings) { return .cloud(model: settings.modelId) }
            if isOnDeviceAvailable { return .onDevice }   // graceful fallback
            return .unavailable
        }
    }

    /// Whether figure/chart analysis can run: user opted in, a cloud key exists,
    /// and the configured model is vision-capable. (On-device can't see images.)
    nonisolated func canAnalyzeFigures(settings: LLMProviderSettings) -> Bool {
        settings.analyzeFigures
            && hasCloudKey
            && LLMModelCapabilities.supportsVision(settings.modelId)
    }

    /// One-shot completion forced through the cloud route (used for multimodal
    /// figure analysis, which the on-device model cannot perform). Throws if no
    /// cloud key is configured.
    func cloudComplete(messages: [LLMMessage], settings: LLMProviderSettings) async throws -> String {
        guard hasCloudKey else { throw LLMError.missingAPIKey }
        let client = OpenAICompatibleLLMClient(
            baseURL: settings.effectiveBaseURL,
            apiKey: KeychainService.get(KeychainService.Account.llmChat)
        )
        return try await client.complete(messages: messages, model: settings.modelId)
    }

    /// Stream a chat completion via the resolved route.
    func stream(messages: [LLMMessage], settings: LLMProviderSettings) -> AsyncThrowingStream<String, Error> {
        switch resolveRoute(settings: settings) {
        case .unavailable:
            return AsyncThrowingStream { $0.finish(throwing: LLMError.notConfigured(
                "No AI provider is available. Add an API key in Settings → AI Providers, or enable Apple Intelligence."
            )) }

        case .onDevice:
            return streamOnDevice(messages: messages)

        case .cloud(let model):
            let client = OpenAICompatibleLLMClient(
                baseURL: settings.effectiveBaseURL,
                apiKey: settings.preset.keychainAccount.flatMap { KeychainService.get($0) }
            )
            return client.stream(messages: messages, model: model)
        }
    }

    // MARK: - On-device

    private func streamOnDevice(messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let instructions = messages.filter { $0.role == .system }
                            .map(\.content).joined(separator: "\n\n")
                        let transcript = messages.filter { $0.role != .system }
                            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
                            .joined(separator: "\n\n")
                        let session = LanguageModelSession(instructions: instructions.isEmpty ? nil : instructions)
                        let response = try await session.respond(to: transcript)
                        continuation.yield(response.content)
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: LLMError.cancelled)
                    } catch {
                        continuation.finish(throwing: LLMError.unavailable(
                            "On-device model error: \(error.localizedDescription)"
                        ))
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: LLMError.unavailable(
            "Apple Intelligence requires macOS 26 and an eligible Mac."
        )) }
    }
}
