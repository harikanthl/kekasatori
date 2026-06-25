//
//  MediaAnalysis.swift
//  MuseDrop
//

import Foundation

enum AIStudyTab: String, CaseIterable, Identifiable {
    case tutor = "Tutor"
    case canvas = "Canvas"
    case notebook = "Notebook"
    case transcript = "Transcript"
    case summary = "Summary"
    case notes = "Notes"
    case flashcards = "Cards"
    case mindMap = "Mind Map"
    case concepts = "Concepts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tutor: return "bubble.left.and.bubble.right.fill"
        case .canvas: return "pencil.and.scribble"
        case .notebook: return "book.closed.fill"
        case .transcript: return "doc.plaintext"
        case .summary: return "text.alignleft"
        case .notes: return "note.text"
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .mindMap: return "point.3.connected.trianglepath.dotted"
        case .concepts: return "lightbulb.fill"
        }
    }
    
    /// Tabs that require a generated study pack.
    var requiresStudyPack: Bool {
        switch self {
        case .tutor, .canvas, .notebook, .transcript: return false
        default: return true
        }
    }
}

enum AIEngineKind: String, Codable {
    case foundationModels
    case naturalLanguageFallback
}

struct MediaTranscript: Codable {
    var text: String
    var createdAt: Date
    var engine: TranscriptionEngine
    /// How much of the source was transcribed (seconds). Nil = full/unknown.
    var coveredSeconds: Double?
    /// Total source duration when known.
    var sourceDurationSeconds: Double?
    /// Human-readable note, e.g. "YouTube captions" or "Sampled 4 segments".
    var coverageNote: String?
    
    init(
        text: String,
        createdAt: Date = Date(),
        engine: TranscriptionEngine = .speechRecognizer,
        coveredSeconds: Double? = nil,
        sourceDurationSeconds: Double? = nil,
        coverageNote: String? = nil
    ) {
        self.text = text
        self.createdAt = createdAt
        self.engine = engine
        self.coveredSeconds = coveredSeconds
        self.sourceDurationSeconds = sourceDurationSeconds
        self.coverageNote = coverageNote
    }
}

struct StudyNotes: Codable {
    var title: String
    var sections: [NoteSection]
    
    init(title: String = "", sections: [NoteSection] = []) {
        self.title = title
        self.sections = sections
    }
}

struct NoteSection: Codable, Identifiable, Hashable {
    var id: String
    var heading: String
    var content: String
    var bullets: [String]
    
    init(id: String = UUID().uuidString, heading: String, content: String, bullets: [String] = []) {
        self.id = id
        self.heading = heading
        self.content = content
        self.bullets = bullets
    }
}

struct KeyConcept: Codable, Identifiable, Hashable {
    var id: String
    var term: String
    var definition: String
    var importance: String
    
    init(id: String = UUID().uuidString, term: String, definition: String, importance: String = "medium") {
        self.id = id
        self.term = term
        self.definition = definition
        self.importance = importance
    }
}

struct FlashCard: Codable, Identifiable, Hashable {
    var id: String
    var front: String
    var back: String
    var tag: String
    
    init(id: String = UUID().uuidString, front: String, back: String, tag: String = "general") {
        self.id = id
        self.front = front
        self.back = back
        self.tag = tag
    }
}

struct MindMapNode: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var level: Int
    
    init(id: String = UUID().uuidString, label: String, level: Int) {
        self.id = id
        self.label = label
        self.level = level
    }
}

struct MindMapEdge: Codable, Identifiable, Hashable {
    var id: String
    var fromId: String
    var toId: String
    var relationship: String
    
    init(id: String = UUID().uuidString, fromId: String, toId: String, relationship: String = "relates to") {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.relationship = relationship
    }
}

struct MindMap: Codable {
    var centralTopic: String
    var nodes: [MindMapNode]
    var edges: [MindMapEdge]
    
    init(centralTopic: String = "", nodes: [MindMapNode] = [], edges: [MindMapEdge] = []) {
        self.centralTopic = centralTopic
        self.nodes = nodes
        self.edges = edges
    }
    
    var primaryNodes: [MindMapNode] {
        nodes.filter { $0.level == 1 }
    }
    
    func children(of nodeId: String) -> [MindMapNode] {
        let childIds = Set(edges.filter { $0.fromId == nodeId }.map(\.toId))
        return nodes.filter { childIds.contains($0.id) }
    }
}

struct MediaAnalysis: Codable, Identifiable {
    var id: UUID
    var downloadId: UUID
    var mediaTitle: String
    var transcript: MediaTranscript
    var summary: SummaryResult
    var notes: StudyNotes
    var keyConcepts: [KeyConcept]
    var flashcards: [FlashCard]
    var mindMap: MindMap
    var engine: AIEngineKind
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        downloadId: UUID,
        mediaTitle: String,
        transcript: MediaTranscript,
        summary: SummaryResult,
        notes: StudyNotes = StudyNotes(),
        keyConcepts: [KeyConcept] = [],
        flashcards: [FlashCard] = [],
        mindMap: MindMap = MindMap(),
        engine: AIEngineKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.downloadId = downloadId
        self.mediaTitle = mediaTitle
        self.transcript = transcript
        self.summary = summary
        self.notes = notes
        self.keyConcepts = keyConcepts
        self.flashcards = flashcards
        self.mindMap = mindMap
        self.engine = engine
        self.createdAt = createdAt
    }
}

extension SummaryResult {
    static func from(oneLine: String, paragraph: String, bullets: [String]) -> SummaryResult {
        SummaryResult(oneLine: oneLine, paragraph: paragraph, bullets: bullets)
    }
}
