//
//  StudyTranslationCoordinator.swift
//  MuseDrop
//
//  Bridges the SwiftUI-only Translation session into async/await so non-view
//  code (the study-pack translator) can request on-device translations.
//
//  A `TranslationSession` can only be vended through the `.translationTask`
//  modifier. The coordinator drives that modifier via a published Configuration
//  and hands the vended session back through a continuation. macOS 15+ (our
//  deployment target is 15.5), so the Translation symbols need no availability gate.
//

import Foundation
import SwiftUI
import Translation

/// A selectable target language for the study-pack translator.
struct TranslationLanguageOption: Identifiable, Hashable {
    /// BCP-47 identifier, e.g. "fr", "pt-BR", "zh-Hans".
    let id: String
    let displayName: String

    var language: Locale.Language { Locale.Language(identifier: id) }

    /// Curated set covering the languages Apple's on-device Translation supports.
    static let common: [TranslationLanguageOption] = [
        .init(id: "en", displayName: "English"),
        .init(id: "es", displayName: "Spanish"),
        .init(id: "fr", displayName: "French"),
        .init(id: "de", displayName: "German"),
        .init(id: "it", displayName: "Italian"),
        .init(id: "pt-BR", displayName: "Portuguese"),
        .init(id: "zh-Hans", displayName: "Chinese (Simplified)"),
        .init(id: "zh-Hant", displayName: "Chinese (Traditional)"),
        .init(id: "ja", displayName: "Japanese"),
        .init(id: "ko", displayName: "Korean"),
        .init(id: "ru", displayName: "Russian"),
        .init(id: "ar", displayName: "Arabic"),
        .init(id: "hi", displayName: "Hindi"),
        .init(id: "nl", displayName: "Dutch"),
        .init(id: "pl", displayName: "Polish"),
        .init(id: "tr", displayName: "Turkish"),
        .init(id: "th", displayName: "Thai"),
        .init(id: "vi", displayName: "Vietnamese"),
        .init(id: "uk", displayName: "Ukrainian"),
        .init(id: "id", displayName: "Indonesian"),
    ]

    /// Best-effort human label for an arbitrary detected language.
    static func displayName(for language: Locale.Language) -> String {
        let code = language.languageCode?.identifier
        if let code, let match = common.first(where: { $0.language.languageCode?.identifier == code }) {
            return match.displayName
        }
        if let code, let localized = Locale.current.localizedString(forLanguageCode: code) {
            return localized.capitalized
        }
        return code ?? "Unknown"
    }
}

@MainActor
final class StudyTranslationCoordinator: ObservableObject {
    /// Drives the `.translationTask` modifier mounted by `studyTranslationHost`.
    @Published var configuration: TranslationSession.Configuration?

    private var pendingRequests: [TranslationSession.Request] = []
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var isBusy = false

    enum BridgeError: LocalizedError {
        case busy
        case unsupportedLanguage(String)

        var errorDescription: String? {
            switch self {
            case .busy:
                return "Another translation is already in progress."
            case .unsupportedLanguage(let name):
                return "On-device translation to \(name) isn’t available on this Mac."
            }
        }
    }

    /// Whether the source → target pair can be translated on device.
    /// A nil source is reported as `.supported`; the batch call auto-detects.
    func availability(from source: Locale.Language?, to target: Locale.Language) async -> LanguageAvailability.Status {
        guard let source else { return .supported }
        return await LanguageAvailability().status(from: source, to: target)
    }

    /// Translates a batch of requests, returning targetText keyed by clientIdentifier.
    func translate(
        _ requests: [TranslationSession.Request],
        from source: Locale.Language?,
        to target: Locale.Language
    ) async throws -> [String: String] {
        guard !requests.isEmpty else { return [:] }
        guard !isBusy else { throw BridgeError.busy }
        isBusy = true
        defer {
            isBusy = false
            configuration = nil
            pendingRequests = []
            continuation = nil
        }

        // Re-translating the same language pair produces an *equal*
        // TranslationSession.Configuration, and `.translationTask` won't re-fire
        // for an unchanged value — the continuation below would hang forever.
        // Clear to nil and yield so the host actually *renders* the teardown,
        // guaranteeing the next configuration is seen as a real nil → value change.
        configuration = nil
        try? await Task.sleep(for: .milliseconds(60))

        return try await withCheckedThrowingContinuation { cont in
            pendingRequests = requests
            continuation = cont
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    /// Invoked by the host `.translationTask` closure once SwiftUI vends a session.
    func fulfillPending(using session: TranslationSession) async {
        guard let cont = continuation else { return }
        continuation = nil
        let requests = pendingRequests
        pendingRequests = []

        do {
            let responses = try await session.translations(from: requests)
            var result: [String: String] = [:]
            result.reserveCapacity(responses.count)
            for response in responses {
                if let id = response.clientIdentifier {
                    result[id] = response.targetText
                }
            }
            cont.resume(returning: result)
        } catch {
            cont.resume(throwing: error)
        }
    }
}

/// Mounts the `.translationTask` and—crucially—*observes* the coordinator, so a
/// change to `configuration` re-evaluates the modifier and re-fires the task.
/// Without `@ObservedObject` here, the host view (which only observes the
/// PlayerViewModel) never re-renders when `configuration` flips nil → value, so
/// the session is never vended and `translate()` hangs forever.
private struct StudyTranslationHost: ViewModifier {
    @ObservedObject var coordinator: StudyTranslationCoordinator

    func body(content: Content) -> some View {
        content.translationTask(coordinator.configuration) { session in
            await coordinator.fulfillPending(using: session)
        }
    }
}

extension View {
    /// Mounts the Translation session that backs `coordinator`. Attach once to a
    /// view that stays alive while translations may be requested.
    func studyTranslationHost(_ coordinator: StudyTranslationCoordinator) -> some View {
        modifier(StudyTranslationHost(coordinator: coordinator))
    }
}
