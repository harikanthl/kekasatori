//
//  StudyPersistenceModels.swift
//  MuseDrop
//
//  SwiftData schema for downloads and AI study artifacts.
//

import Foundation
import SwiftData

enum AIStudyArtifactKind: String, Codable, CaseIterable {
    case transcript
    case summary
    case notes
    case flashcards
    case mindMap
    case concepts
    case fullPack
    case regenerated
}

@Model
final class DownloadRecord {
    @Attribute(.unique) var id: UUID
    var url: String
    var title: String
    var thumbnailPath: String?
    var format: String
    var progress: Double
    var statusRaw: String
    var outputPath: String?
    var createdAt: Date
    var errorMessage: String?
    
    var consumptionModeRaw: String
    var streamURLString: String?
    var streamExpiresAt: Date?
    var streamMediaKindRaw: String?
    var durationSeconds: Double?
    
    @Relationship(deleteRule: .cascade, inverse: \StudySessionRecord.download)
    var studySession: StudySessionRecord?
    
    @Relationship(deleteRule: .cascade, inverse: \CanvasBoardRecord.download)
    var canvasBoards: [CanvasBoardRecord]
    
    @Relationship(deleteRule: .cascade, inverse: \UserNotebookEntryRecord.download)
    var notebookEntries: [UserNotebookEntryRecord]
    
    init(
        id: UUID = UUID(),
        url: String,
        title: String = "",
        thumbnailPath: String? = nil,
        format: String = "",
        progress: Double = 0,
        statusRaw: String = DownloadStatus.queued.rawValue,
        outputPath: String? = nil,
        createdAt: Date = Date(),
        errorMessage: String? = nil,
        consumptionModeRaw: String = ConsumptionMode.download.rawValue,
        streamURLString: String? = nil,
        streamExpiresAt: Date? = nil,
        streamMediaKindRaw: String? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.thumbnailPath = thumbnailPath
        self.format = format
        self.progress = progress
        self.statusRaw = statusRaw
        self.outputPath = outputPath
        self.createdAt = createdAt
        self.errorMessage = errorMessage
        self.consumptionModeRaw = consumptionModeRaw
        self.streamURLString = streamURLString
        self.streamExpiresAt = streamExpiresAt
        self.streamMediaKindRaw = streamMediaKindRaw
        self.durationSeconds = durationSeconds
        self.canvasBoards = []
        self.notebookEntries = []
    }
}

@Model
final class StudySessionRecord {
    @Attribute(.unique) var id: UUID
    var mediaTitle: String
    var engineRaw: String
    var createdAt: Date
    var updatedAt: Date
    
    var summaryOneLine: String
    var summaryParagraph: String
    
    var notesTitle: String
    var mindMapCentralTopic: String
    /// Fingerprint of the source file/URL this session belongs to.
    var sourceMediaKey: String = ""

    // MARK: Organization (additive — lightweight migration safe)
    /// Shu-Ha-Ri mastery stage; nil means unset. Stores `MasteryStage.rawValue`.
    var masteryStageRaw: String?
    /// User-pinned/favorite pack (floats to the top of lists).
    var isPinned: Bool = false
    /// Last time the user opened this pack to study (drives "recently studied").
    var lastStudiedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptRecord.studySession)
    var transcript: TranscriptRecord?
    
    @Relationship(deleteRule: .cascade, inverse: \OrderedTextRecord.summarySession)
    var summaryBullets: [OrderedTextRecord]
    
    @Relationship(deleteRule: .cascade, inverse: \NoteSectionRecord.studySession)
    var noteSections: [NoteSectionRecord]
    
    @Relationship(deleteRule: .cascade, inverse: \FlashcardRecord.studySession)
    var flashcards: [FlashcardRecord]
    
    @Relationship(deleteRule: .cascade, inverse: \KeyConceptRecord.studySession)
    var keyConcepts: [KeyConceptRecord]
    
    @Relationship(deleteRule: .cascade, inverse: \MindMapNodeRecord.studySession)
    var mindMapNodes: [MindMapNodeRecord]
    
    @Relationship(deleteRule: .cascade, inverse: \MindMapEdgeRecord.studySession)
    var mindMapEdges: [MindMapEdgeRecord]
    
    @Relationship(deleteRule: .cascade, inverse: \StudyArtifactRecord.studySession)
    var artifactHistory: [StudyArtifactRecord]
    
    var download: DownloadRecord?
    
    init(
        id: UUID = UUID(),
        mediaTitle: String,
        engineRaw: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        summaryOneLine: String = "",
        summaryParagraph: String = "",
        notesTitle: String = "",
        mindMapCentralTopic: String = "",
        sourceMediaKey: String = ""
    ) {
        self.id = id
        self.mediaTitle = mediaTitle
        self.engineRaw = engineRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.summaryOneLine = summaryOneLine
        self.summaryParagraph = summaryParagraph
        self.notesTitle = notesTitle
        self.mindMapCentralTopic = mindMapCentralTopic
        self.sourceMediaKey = sourceMediaKey
        self.summaryBullets = []
        self.noteSections = []
        self.flashcards = []
        self.keyConcepts = []
        self.mindMapNodes = []
        self.mindMapEdges = []
        self.artifactHistory = []
    }
}

@Model
final class TranscriptRecord {
    var text: String
    var createdAt: Date
    var engineRaw: String
    var coveredSeconds: Double?
    var sourceDurationSeconds: Double?
    var coverageNote: String?
    var studySession: StudySessionRecord?
    
    init(
        text: String,
        createdAt: Date = Date(),
        engineRaw: String = TranscriptionEngine.speechRecognizer.rawValue,
        coveredSeconds: Double? = nil,
        sourceDurationSeconds: Double? = nil,
        coverageNote: String? = nil
    ) {
        self.text = text
        self.createdAt = createdAt
        self.engineRaw = engineRaw
        self.coveredSeconds = coveredSeconds
        self.sourceDurationSeconds = sourceDurationSeconds
        self.coverageNote = coverageNote
    }
}

@Model
final class StudyArtifactRecord {
    var kindRaw: String
    var generatedAt: Date
    var engineRaw: String
    var studySession: StudySessionRecord?
    
    init(kindRaw: String, generatedAt: Date = Date(), engineRaw: String) {
        self.kindRaw = kindRaw
        self.generatedAt = generatedAt
        self.engineRaw = engineRaw
    }
}

@Model
final class OrderedTextRecord {
    var order: Int
    var text: String
    var summarySession: StudySessionRecord?
    var noteSection: NoteSectionRecord?
    
    init(order: Int, text: String) {
        self.order = order
        self.text = text
    }
}

@Model
final class NoteSectionRecord {
    var order: Int
    var heading: String
    var content: String
    var studySession: StudySessionRecord?
    
    @Relationship(deleteRule: .cascade, inverse: \OrderedTextRecord.noteSection)
    var bullets: [OrderedTextRecord]
    
    init(order: Int, heading: String, content: String, bullets: [OrderedTextRecord] = []) {
        self.order = order
        self.heading = heading
        self.content = content
        self.bullets = bullets
    }
}

@Model
final class FlashcardRecord {
    var order: Int
    var front: String
    var back: String
    var tag: String
    var studySession: StudySessionRecord?
    
    init(order: Int, front: String, back: String, tag: String) {
        self.order = order
        self.front = front
        self.back = back
        self.tag = tag
    }
}

@Model
final class KeyConceptRecord {
    var order: Int
    var term: String
    var definition: String
    var importance: String
    var studySession: StudySessionRecord?
    
    init(order: Int, term: String, definition: String, importance: String) {
        self.order = order
        self.term = term
        self.definition = definition
        self.importance = importance
    }
}

@Model
final class MindMapNodeRecord {
    var nodeId: String
    var label: String
    var level: Int
    var studySession: StudySessionRecord?
    
    init(nodeId: String, label: String, level: Int) {
        self.nodeId = nodeId
        self.label = label
        self.level = level
    }
}

@Model
final class MindMapEdgeRecord {
    var edgeId: String
    var fromId: String
    var toId: String
    var relationship: String
    var studySession: StudySessionRecord?
    
    init(edgeId: String, fromId: String, toId: String, relationship: String) {
        self.edgeId = edgeId
        self.fromId = fromId
        self.toId = toId
        self.relationship = relationship
    }
}
