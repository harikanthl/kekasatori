//
//  StudyPackTranslator.swift
//  MuseDrop
//
//  Pure mapping between a study pack's text and Translation batch requests.
//  Every translatable string gets a stable clientIdentifier path so responses
//  can be reassembled back into the model regardless of arrival order.
//

import Foundation
import NaturalLanguage
import Translation

enum StudyPackTranslator {

    // MARK: - Source detection

    /// Best-effort dominant language of a body of text. Nil when undetectable.
    static func detectLanguage(of text: String) -> Locale.Language? {
        let sample = String(text.prefix(2_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let lang = recognizer.dominantLanguage else { return nil }
        return Locale.Language(identifier: lang.rawValue)
    }

    static func isEnglish(_ language: Locale.Language?) -> Bool {
        language?.languageCode?.identifier == "en"
    }

    // MARK: - Transcript

    private static let transcriptChunkPrefix = "transcript.chunk."

    /// Sentence-aware chunks (no overlap — overlap would duplicate text on rejoin).
    private static func transcriptChunks(_ text: String) -> [String] {
        TextChunker.chunk(text, maxChars: 900, overlap: 0)
    }

    static func requests(for transcript: MediaTranscript) -> [TranslationSession.Request] {
        transcriptChunks(transcript.text).enumerated().map { index, chunk in
            TranslationSession.Request(sourceText: chunk, clientIdentifier: "\(transcriptChunkPrefix)\(index)")
        }
    }

    static func applyTranscript(_ translations: [String: String], to transcript: MediaTranscript) -> MediaTranscript {
        let chunks = transcriptChunks(transcript.text)
        guard !chunks.isEmpty else { return transcript }
        let joined = chunks.enumerated()
            .map { translations["\(transcriptChunkPrefix)\($0.offset)"] ?? $0.element }
            .joined(separator: " ")
        var copy = transcript
        copy.text = joined
        return copy
    }

    // MARK: - Full pack

    static func requests(for analysis: MediaAnalysis, includeTranscript: Bool) -> [TranslationSession.Request] {
        var reqs: [TranslationSession.Request] = []

        func add(_ id: String, _ text: String) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            reqs.append(TranslationSession.Request(sourceText: text, clientIdentifier: id))
        }

        if includeTranscript {
            reqs.append(contentsOf: requests(for: analysis.transcript))
        }

        add("summary.oneLine", analysis.summary.oneLine)
        add("summary.paragraph", analysis.summary.paragraph)
        for (i, bullet) in analysis.summary.bullets.enumerated() {
            add("summary.bullet.\(i)", bullet)
        }

        add("notes.title", analysis.notes.title)
        for (i, section) in analysis.notes.sections.enumerated() {
            add("notes.section.\(i).heading", section.heading)
            add("notes.section.\(i).content", section.content)
            for (j, bullet) in section.bullets.enumerated() {
                add("notes.section.\(i).bullet.\(j)", bullet)
            }
        }

        for (i, card) in analysis.flashcards.enumerated() {
            add("flashcard.\(i).front", card.front)
            add("flashcard.\(i).back", card.back)
        }

        for (i, concept) in analysis.keyConcepts.enumerated() {
            add("concept.\(i).term", concept.term)
            add("concept.\(i).definition", concept.definition)
        }

        add("mindmap.central", analysis.mindMap.centralTopic)
        for (i, node) in analysis.mindMap.nodes.enumerated() {
            add("mindmap.node.\(i)", node.label)
        }
        for (i, edge) in analysis.mindMap.edges.enumerated() {
            add("mindmap.edge.\(i)", edge.relationship)
        }

        return reqs
    }

    /// Rebuilds `analysis` with translated strings, leaving ids/tags/levels intact.
    /// Missing translations fall back to the original text.
    static func apply(_ tr: [String: String], to analysis: MediaAnalysis, includeTranscript: Bool) -> MediaAnalysis {
        func g(_ id: String, _ original: String) -> String { tr[id] ?? original }

        var copy = analysis

        if includeTranscript {
            copy.transcript = applyTranscript(tr, to: analysis.transcript)
        }

        copy.summary.oneLine = g("summary.oneLine", analysis.summary.oneLine)
        copy.summary.paragraph = g("summary.paragraph", analysis.summary.paragraph)
        copy.summary.bullets = analysis.summary.bullets.enumerated().map {
            g("summary.bullet.\($0.offset)", $0.element)
        }

        copy.notes.title = g("notes.title", analysis.notes.title)
        copy.notes.sections = analysis.notes.sections.enumerated().map { idx, section in
            var ns = section
            ns.heading = g("notes.section.\(idx).heading", section.heading)
            ns.content = g("notes.section.\(idx).content", section.content)
            ns.bullets = section.bullets.enumerated().map {
                g("notes.section.\(idx).bullet.\($0.offset)", $0.element)
            }
            return ns
        }

        copy.flashcards = analysis.flashcards.enumerated().map { idx, card in
            var nc = card
            nc.front = g("flashcard.\(idx).front", card.front)
            nc.back = g("flashcard.\(idx).back", card.back)
            return nc
        }

        copy.keyConcepts = analysis.keyConcepts.enumerated().map { idx, concept in
            var nk = concept
            nk.term = g("concept.\(idx).term", concept.term)
            nk.definition = g("concept.\(idx).definition", concept.definition)
            return nk
        }

        copy.mindMap.centralTopic = g("mindmap.central", analysis.mindMap.centralTopic)
        copy.mindMap.nodes = analysis.mindMap.nodes.enumerated().map { idx, node in
            var nn = node
            nn.label = g("mindmap.node.\(idx)", node.label)
            return nn
        }
        copy.mindMap.edges = analysis.mindMap.edges.enumerated().map { idx, edge in
            var ne = edge
            ne.relationship = g("mindmap.edge.\(idx)", edge.relationship)
            return ne
        }

        return copy
    }
}
