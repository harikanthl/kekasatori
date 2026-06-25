//
//  AnalysisText.swift
//  MuseDrop
//
//  Transcript preparation for on-device language models.
//

import Foundation
import NaturalLanguage

enum AnalysisText {
    /// Apple on-device FM context window (TN3193).
    static let foundationModelContextWindow = 4_096
    
    /// Transcript tokens budget for a single LanguageModelSession call.
    /// Leaves room for instructions, @Generable schema, and model output (~4096 total).
    static let perSessionTranscriptTokens = 900
    
    /// Chunk size for map-reduce summarization of long transcripts.
    static let mapReduceChunkTokens = 650
    
    /// Cap FM round-trips for very long lectures (each chunk = one on-device session).
    static let maxMapReduceChunks = 10
    
    /// Output density scaled to lecture length (on-device FM has small context per call).
    struct StudyPackScale {
        enum LectureLength: String {
            case short
            case medium
            case long
        }
        
        let length: LectureLength
        let estimatedTokens: Int
        let chunkCount: Int
        let targetNoteSections: Int
        let targetFlashcards: Int
        let targetConcepts: Int
        let targetMindMapNodes: Int
        let sectionsPerChunk: ClosedRange<Int>
        let cardsPerChunk: ClosedRange<Int>
        let conceptsPerChunk: ClosedRange<Int>
        
        var usesMapReduce: Bool { chunkCount > 1 }
        
        static func from(transcript: String) -> StudyPackScale {
            let normalized = AnalysisText.normalize(transcript)
            let tokens = AnalysisText.estimatedTokens(for: normalized)
            let chunks = AnalysisText.mapReduceChunks(from: normalized)
            let chunkCount = max(1, chunks.count)
            
            switch tokens {
            case ..<2_500:
                return StudyPackScale(
                    length: .short,
                    estimatedTokens: tokens,
                    chunkCount: chunkCount,
                    targetNoteSections: 4,
                    targetFlashcards: 10,
                    targetConcepts: 6,
                    targetMindMapNodes: 10,
                    sectionsPerChunk: 2...4,
                    cardsPerChunk: 4...6,
                    conceptsPerChunk: 2...4
                )
            case 2_500..<10_000:
                return StudyPackScale(
                    length: .medium,
                    estimatedTokens: tokens,
                    chunkCount: chunkCount,
                    targetNoteSections: 7,
                    targetFlashcards: 16,
                    targetConcepts: 10,
                    targetMindMapNodes: 14,
                    sectionsPerChunk: 2...4,
                    cardsPerChunk: 4...6,
                    conceptsPerChunk: 2...4
                )
            default:
                let sectionTarget = min(16, max(10, chunkCount * 2))
                let cardTarget = min(30, max(18, chunkCount * 2))
                let conceptTarget = min(24, max(14, chunkCount * 2))
                let mindMapTarget = min(28, max(16, chunkCount * 2))
                return StudyPackScale(
                    length: .long,
                    estimatedTokens: tokens,
                    chunkCount: chunkCount,
                    targetNoteSections: sectionTarget,
                    targetFlashcards: cardTarget,
                    targetConcepts: conceptTarget,
                    targetMindMapNodes: mindMapTarget,
                    sectionsPerChunk: 2...5,
                    cardsPerChunk: 3...6,
                    conceptsPerChunk: 2...5
                )
            }
        }
    }
    
    /// Hard ceiling on transcript characters fed into on-device analysis. Bounds
    /// NL tokenization and the O(n·m) fallback sentence ranking against
    /// pathological inputs (multi-hour captions, dense 120-page PDFs). The full
    /// transcript is still stored for display — only the analysis input is clamped.
    static let maxAnalysisCharacters = 240_000

    /// Truncates near the limit on a sentence/whitespace boundary so analysis
    /// input stays bounded without cutting mid-word. Returns the text unchanged
    /// when it is already within the ceiling.
    static func clampedForAnalysis(_ text: String) -> String {
        guard text.count > maxAnalysisCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxAnalysisCharacters)
        let slice = text[..<end]
        if let lastBreak = slice.lastIndex(where: { $0 == "." || $0 == "\n" || $0 == " " }) {
            return String(slice[..<lastBreak])
        }
        return String(slice)
    }

    /// Chars-per-token heuristic for English (TN3193: ~3–4 chars/token).
    static func estimatedTokens(for text: String) -> Int {
        max(1, text.count / 4)
    }
    
    /// Sentence-bounded chunks sized for per-chunk summarization sessions.
    static func mapReduceChunks(from transcript: String, maxTokens: Int = mapReduceChunkTokens) -> [String] {
        let normalized = normalize(transcript)
        let maxCharacters = max(1_200, maxTokens * 4)
        guard estimatedTokens(for: normalized) > perSessionTranscriptTokens else {
            return [normalized]
        }
        
        let sentences = sentenceChunks(from: normalized)
        guard !sentences.isEmpty else {
            return strideChunks(from: normalized, maxCharacters: maxCharacters)
        }
        
        var chunks: [String] = []
        var current = ""
        
        for sentence in sentences {
            let candidate = current.isEmpty ? sentence : current + " " + sentence
            if candidate.count <= maxCharacters {
                current = candidate
                continue
            }
            if !current.isEmpty {
                chunks.append(current)
            }
            if sentence.count <= maxCharacters {
                current = sentence
            } else {
                chunks.append(contentsOf: strideChunks(from: sentence, maxCharacters: maxCharacters))
                current = ""
            }
        }
        
        if !current.isEmpty {
            chunks.append(current)
        }
        
        let bounded = chunks.isEmpty ? [prepare(normalized, maxTokens: maxTokens)] : chunks
        return capMapReduceChunks(bounded, maxChunks: maxMapReduceChunks)
    }
    
    /// Merge adjacent chunks when a long lecture would exceed the on-device FM call budget.
    private static func capMapReduceChunks(_ chunks: [String], maxChunks: Int) -> [String] {
        guard chunks.count > maxChunks else { return chunks }
        
        var merged: [String] = []
        let groupSize = Int(ceil(Double(chunks.count) / Double(maxChunks)))
        
        var index = 0
        while index < chunks.count {
            let end = min(index + groupSize, chunks.count)
            merged.append(chunks[index..<end].joined(separator: "\n\n"))
            index = end
        }
        
        return merged
    }
    
    /// Legacy alias — prefer perSessionTranscriptTokens for Foundation Models.
    static let defaultMaxTokens = perSessionTranscriptTokens
    
    /// Richer grounding for single-pass generation on shorter lectures.
    static func studyContext(
        title: String,
        oneLine: String,
        paragraph: String,
        bullets: [String],
        transcript: String,
        researchBlock: String = "",
        scale: StudyPackScale
    ) -> String {
        let excerptTokens: Int = switch scale.length {
        case .short: 700
        case .medium: 500
        case .long: 350
        }
        return studyContext(
            title: title,
            oneLine: oneLine,
            paragraph: paragraph,
            bullets: bullets,
            transcript: transcript,
            researchBlock: researchBlock,
            excerptTokens: excerptTokens
        )
    }
    
    /// Compact grounding block passed to downstream artifact sessions (summary + excerpt).
    static func studyContext(
        title: String,
        oneLine: String,
        paragraph: String,
        bullets: [String],
        transcript: String,
        researchBlock: String = "",
        excerptTokens: Int = 350
    ) -> String {
        let bulletText = bullets.map { "- \($0)" }.joined(separator: "\n")
        let excerpt = prepare(transcript, maxTokens: excerptTokens)
        
        return """
        Title: \(title)\(researchBlock)
        
        Lecture summary:
        \(oneLine)
        
        \(paragraph)
        
        Key points:
        \(bulletText)
        
        Transcript excerpt (ground answers here; do not invent beyond this):
        \(excerpt)
        """
    }
    
    static func prepare(_ transcript: String, maxTokens: Int = perSessionTranscriptTokens) -> String {
        let normalized = normalize(transcript)
        let maxCharacters = max(4_000, maxTokens * 4)
        guard normalized.count > maxCharacters else { return normalized }
        
        let chunks = sentenceChunks(from: normalized)
        guard chunks.count > 1 else {
            return truncateMiddle(normalized, maxCharacters: maxCharacters)
        }
        
        // Keep opening context + evenly spaced samples + closing context.
        let headBudget = maxCharacters * 45 / 100
        let tailBudget = maxCharacters * 20 / 100
        let sampleBudget = maxCharacters - headBudget - tailBudget
        
        var head = ""
        var tail = ""
        var middleSamples: [String] = []
        
        // Always treat at least the final chunk as tail material so short
        // transcripts still keep their closing context (the proportional
        // window below can round to zero for few chunks).
        let tailWindow = max(1, chunks.count / 4)

        for (index, chunk) in chunks.enumerated() {
            if head.count + chunk.count + 1 <= headBudget {
                head += (head.isEmpty ? "" : " ") + chunk
                continue
            }

            let reverseIndex = chunks.count - 1 - index
            if tail.count + chunk.count + 1 <= tailBudget, reverseIndex < tailWindow {
                tail = chunk + (tail.isEmpty ? "" : " ") + tail
                continue
            }

            if index % max(1, chunks.count / 6) == 0 {
                middleSamples.append(chunk)
            }
        }

        var sampledMiddle = ""
        for sample in middleSamples {
            guard sampledMiddle.count + sample.count + 2 <= sampleBudget else { break }
            sampledMiddle += (sampledMiddle.isEmpty ? "" : "\n") + sample
        }

        // Only emit scaffolding for sections that actually have content so we
        // never inject confusing placeholders around empty blocks.
        var parts: [String] = []
        if !head.isEmpty {
            parts.append(head)
        }
        if !sampledMiddle.isEmpty {
            parts.append("[... sampled middle sections omitted for context window ...]")
            parts.append(sampledMiddle)
        }
        if !tail.isEmpty {
            parts.append("[... end of transcript ...]")
            parts.append(tail)
        }
        return parts.joined(separator: "\n\n")
    }
    
    static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func sentenceChunks(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 12 {
                sentences.append(sentence)
            }
            return true
        }
        
        if sentences.isEmpty {
            return text.components(separatedBy: ". ").filter { $0.count > 12 }
        }
        return sentences
    }
    
    private static func truncateMiddle(_ text: String, maxCharacters: Int) -> String {
        let prefix = text.prefix(maxCharacters * 2 / 3)
        let suffix = text.suffix(maxCharacters / 3)
        return "\(prefix)\n\n[... middle truncated for context ...]\n\n\(suffix)"
    }
    
    private static func strideChunks(from text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }
}
