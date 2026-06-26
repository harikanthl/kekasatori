//
//  StudyPackSummary.swift
//  MuseDrop
//

import Foundation

struct StudyPackSummary: Identifiable, Hashable, Sendable {
    let downloadId: UUID
    let sessionId: UUID
    let mediaTitle: String
    let summaryOneLine: String
    let thumbnailPath: String?
    let createdAt: Date
    let updatedAt: Date
    let engineRaw: String
    let isCompletePack: Bool
    let hasTranscript: Bool
    let flashcardCount: Int
    let noteSectionCount: Int
    let conceptCount: Int
    let generationCount: Int
    let lastGeneratedAt: Date?
    let lastArtifactKindRaw: String?
    let isStreamOnly: Bool
    let isResearchDocument: Bool
    let isAudioMedia: Bool
    // Mutable so the view model can reflect a change in-memory without a full
    // SwiftData refetch (the persistence write still happens via DataStore).
    var masteryStageRaw: String?
    var isPinned: Bool
    var lastStudiedAt: Date?

    var id: UUID { downloadId }

    /// Shu-Ha-Ri mastery stage, if the user has set one.
    var masteryStage: MasteryStage? {
        masteryStageRaw.flatMap(MasteryStage.init(rawValue:))
    }
    
    var displayTitle: String {
        let trimmed = mediaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled media" : trimmed
    }
    
    var statusLabel: String {
        if isCompletePack { return "Full pack" }
        if hasTranscript { return "Transcript" }
        return "Partial"
    }
    
    var engineLabel: String {
        switch engineRaw {
        case AIEngineKind.foundationModels.rawValue:
            return "Apple Intelligence"
        case AIEngineKind.naturalLanguageFallback.rawValue:
            return "Fallback engine"
        default:
            return engineRaw
        }
    }
}
