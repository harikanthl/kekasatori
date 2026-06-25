//
//  FallbackAnalysisService.swift
//  MuseDrop
//
//  NaturalLanguage-based fallback when Foundation Models are unavailable.
//

import Foundation
import NaturalLanguage

enum FallbackAnalysisService {
    static func analyze(
        transcript: String,
        title: String,
        researchContext: String? = nil,
        variationSeed: UInt64 = 0
    ) -> MediaAnalysisPayload {
        let scale = AnalysisText.StudyPackScale.from(transcript: transcript)
        let sentences = splitSentences(from: transcript)
        let ranked = rankSentences(sentences, in: transcript)
        let rotated = rotate(ranked, seed: variationSeed)
        
        let oneLine = rotated.first?.sentence ?? title
        let paragraph = rotated.prefix(scale.length == .long ? 8 : 4).map(\.sentence).joined(separator: " ")
        let bullets = rotated.prefix(scale.length == .long ? 10 : 6).map(\.sentence)
        
        var sections = buildNoteSections(from: rotated, title: title, scale: scale)
        if let researchContext, !researchContext.isEmpty {
            sections.append(
                NoteSection(
                    heading: "External context",
                    content: researchContext,
                    bullets: []
                )
            )
        }
        
        let concepts = buildConcepts(from: rotated, limit: scale.targetConcepts)
        let cards = buildFlashcards(from: concepts, ranked: rotated, seed: variationSeed, limit: scale.targetFlashcards)
        let mindMap = buildMindMap(title: title, concepts: concepts, scale: scale)
        
        return MediaAnalysisPayload(
            summary: SummaryResult.from(oneLine: oneLine, paragraph: paragraph, bullets: bullets),
            notes: StudyNotes(title: "\(title) — Study Notes", sections: sections),
            keyConcepts: concepts,
            flashcards: cards,
            mindMap: mindMap,
            engine: .naturalLanguageFallback
        )
    }
    
    private static func rotate(_ ranked: [RankedSentence], seed: UInt64) -> [RankedSentence] {
        guard !ranked.isEmpty, seed > 0 else { return ranked }
        let offset = Int(seed % UInt64(max(ranked.count, 1) / 3 + 1))
        guard offset > 0 else { return ranked }
        return Array(ranked.dropFirst(offset)) + ranked.prefix(offset)
    }
    
    private struct RankedSentence {
        let sentence: String
        let score: Double
    }
    
    private static func splitSentences(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 20 {
                sentences.append(sentence)
            }
            return true
        }
        
        if sentences.isEmpty {
            return text.components(separatedBy: ". ").filter { $0.count > 20 }
        }
        return sentences
    }
    
    private static func rankSentences(_ sentences: [String], in text: String) -> [RankedSentence] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        
        let keywords = Set(extractKeywords(from: text))
        
        let ranked = sentences.map { sentence -> RankedSentence in
            var score = Double(sentence.count) / 120.0
            
            for keyword in keywords {
                if sentence.localizedCaseInsensitiveContains(keyword) {
                    score += 1.2
                }
            }
            
            let cueWords = ["important", "key", "remember", "therefore", "because", "concept", "define"]
            for cue in cueWords where sentence.localizedCaseInsensitiveContains(cue) {
                score += 0.6
            }
            
            return RankedSentence(sentence: sentence, score: score)
        }
        
        return ranked.sorted { $0.score > $1.score }
    }
    
    private static func extractKeywords(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        
        var keywords: [String: Int] = [:]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            guard tag == .noun || tag == .verb else { return true }
            let word = String(text[range]).lowercased()
            guard word.count > 4 else { return true }
            keywords[word, default: 0] += 1
            return true
        }
        
        return keywords.sorted { $0.value > $1.value }.prefix(8).map(\.key)
    }
    
    private static func buildNoteSections(
        from ranked: [RankedSentence],
        title: String,
        scale: AnalysisText.StudyPackScale
    ) -> [NoteSection] {
        let overviewCount = scale.length == .long ? 5 : 3
        let detailCount = scale.length == .long ? 10 : 4
        let takeawayCount = scale.length == .long ? 8 : 5
        
        let overview = ranked.prefix(overviewCount).map(\.sentence).joined(separator: " ")
        let details = ranked.dropFirst(overviewCount).prefix(detailCount).map(\.sentence)
        let takeaways = ranked.prefix(takeawayCount).map(\.sentence)
        
        var sections = [
            NoteSection(heading: "Overview", content: overview, bullets: []),
            NoteSection(heading: "Core Ideas", content: "", bullets: details),
            NoteSection(heading: "Takeaways", content: "", bullets: takeaways)
        ]
        
        if scale.length == .long {
            let examples = ranked.dropFirst(overviewCount + detailCount).prefix(6).map(\.sentence)
            sections.append(NoteSection(heading: "Examples & Details", content: "", bullets: examples))
        }
        
        return sections
    }
    
    private static func buildConcepts(from ranked: [RankedSentence], limit: Int) -> [KeyConcept] {
        ranked.prefix(limit).enumerated().map { index, item in
            let words = item.sentence.split(separator: " ")
            let term = words.prefix(4).joined(separator: " ")
            let importance = index < 2 ? "high" : (index < 4 ? "medium" : "low")
            return KeyConcept(term: term, definition: item.sentence, importance: importance)
        }
    }
    
    private static func buildFlashcards(
        from concepts: [KeyConcept],
        ranked: [RankedSentence],
        seed: UInt64 = 0,
        limit: Int
    ) -> [FlashCard] {
        var cards = concepts.prefix(min(8, limit)).map {
            FlashCard(front: "What is \($0.term)?", back: $0.definition, tag: "concept")
        }

        let recallSlots = max(0, limit - cards.count)
        // Offset into ranked sentences for variety (skip the highest-ranked few
        // already used for concepts, plus a seed-based jitter), but never so far
        // that the pool can't supply the recall cards we still need.
        let baseSkip = min(6, max(0, ranked.count - recallSlots))
        let maxOffset = max(0, ranked.count - recallSlots - baseSkip)
        let jitter = maxOffset > 0 ? Int(seed % UInt64(maxOffset + 1)) : 0
        let pool = Array(ranked.dropFirst(baseSkip + jitter))

        for sentence in pool.prefix(recallSlots) {
            cards.append(
                FlashCard(
                    front: "Explain: \(sentence.sentence.prefix(80))…",
                    back: sentence.sentence,
                    tag: "recall"
                )
            )
        }
        
        return Array(cards.prefix(limit))
    }
    
    private static func buildMindMap(
        title: String,
        concepts: [KeyConcept],
        scale: AnalysisText.StudyPackScale
    ) -> MindMap {
        let center = MindMapNode(id: "center", label: title, level: 0)
        var nodes: [MindMapNode] = [center]
        var edges: [MindMapEdge] = []
        
        let branchLimit = min(scale.targetMindMapNodes / 2, concepts.count)
        for (index, concept) in concepts.prefix(branchLimit).enumerated() {
            let nodeId = "branch-\(index)"
            nodes.append(MindMapNode(id: nodeId, label: concept.term, level: 1))
            edges.append(MindMapEdge(fromId: center.id, toId: nodeId, relationship: "includes"))
            
            let childId = "leaf-\(index)"
            nodes.append(MindMapNode(id: childId, label: String(concept.definition.prefix(48)), level: 2))
            edges.append(MindMapEdge(fromId: nodeId, toId: childId, relationship: "explained by"))
        }
        
        return MindMap(centralTopic: title, nodes: nodes, edges: edges)
    }
}
