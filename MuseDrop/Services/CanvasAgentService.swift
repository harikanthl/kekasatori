//
//  CanvasAgentService.swift
//  MuseDrop
//
//  Agent-facing canvas tools (StudyAgent integration hooks).
//

import Foundation

enum CanvasAgentService {
    
    /// Push summary bullets, concept terms, or flashcard fronts as text blocks.
    static func pushToCanvas(
        texts: [String],
        boardTitle: String? = nil
    ) -> CanvasElementBatch {
        let header = boardTitle.map { ["\($0)"] } ?? []
        return CanvasElementBatch.textBlocks(texts: header + texts)
    }
    
    static func pushSummaryBullets(_ bullets: [String]) -> CanvasElementBatch {
        pushToCanvas(texts: bullets, boardTitle: "Summary")
    }
    
    static func pushConcepts(_ concepts: [KeyConcept]) -> CanvasElementBatch {
        let lines = concepts.map { "\($0.term): \($0.definition)" }
        return pushToCanvas(texts: lines, boardTitle: "Key Concepts")
    }
    
    static func pushFlashcards(_ cards: [FlashCard]) -> CanvasElementBatch {
        let lines = cards.map { "Q: \($0.front)\nA: \($0.back)" }
        return pushToCanvas(texts: lines, boardTitle: "Flashcards")
    }
    
    /// Future StudyAgent tool: auto-layout related items on the canvas.
    static func organizeCanvasLayoutHint() -> String {
        "Group elements by topic, align in columns, and connect with arrows."
    }
    
    /// Future StudyAgent tool: explain a selected canvas region.
    static func generateFromSelectionPrompt(selectionDescription: String, lectureTitle: String) -> String {
        """
        Explain the ideas in this canvas selection from lecture "\(lectureTitle)".
        Selection: \(selectionDescription)
        """
    }
    
    static func encodeBatch(_ batch: CanvasElementBatch) -> String? {
        let wrapper = ["elements": batch.elements.map { element in
            element.mapValues { $0.jsonValue }
        }]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private extension AnyCodableValue {
    var jsonValue: Any {
        switch self {
        case .string(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map(\.jsonValue)
        case .null: return NSNull()
        }
    }
}
