//
//  TextChunker.swift
//  MuseDrop
//
//  Splits long paper/transcript text into overlapping, sentence-aware chunks
//  sized for embedding + retrieval.
//

import Foundation
import NaturalLanguage

enum TextChunker {
    /// Target characters per chunk and overlap between consecutive chunks.
    static func chunk(_ text: String, maxChars: Int = 900, overlap: Int = 120) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        guard normalized.count > maxChars else { return [normalized] }

        // Sentence-segment, then greedily pack sentences into chunks.
        let sentences = sentences(in: normalized)
        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= maxChars {
                current += " " + sentence
            } else {
                chunks.append(current)
                // Start the next chunk with a tail overlap for context continuity.
                let tail = String(current.suffix(overlap))
                current = tail.isEmpty ? sentence : tail + " " + sentence
            }
            // A single sentence longer than maxChars: hard-split it.
            while current.count > maxChars + overlap {
                let cut = current.index(current.startIndex, offsetBy: maxChars)
                chunks.append(String(current[..<cut]))
                current = String(current[cut...])
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
            return true
        }
        return result.isEmpty ? [text] : result
    }
}
