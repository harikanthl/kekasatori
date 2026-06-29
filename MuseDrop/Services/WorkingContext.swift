//
//  WorkingContext.swift
//  MuseDrop
//
//  Phase M2: assemble recalled memories into the working-memory block an agent
//  turn is primed with (docs/agentic-memory.md). Recall ranks; this packs the top
//  memories into a token budget. Pure assembler (testable) + a `MemoryStore`
//  convenience that recalls then assembles. The agent (G) calls `workingContext`
//  to ground each turn.
//

import Foundation

enum WorkingContext {
    /// Rough chars-per-token for budgeting (good enough for a soft cap; the model
    /// tokenizer is the real authority, but we never want to over-pack).
    static let approxCharsPerToken = 4

    static func estimateTokens(_ text: String) -> Int {
        (text.count + approxCharsPerToken - 1) / approxCharsPerToken
    }

    /// Pack memories (already ranked, most-relevant first) into a labelled block
    /// that fits `tokenBudget`. Returns "" when nothing fits.
    static func assemble(
        from memories: [Memory],
        tokenBudget: Int,
        header: String = "Relevant memory:"
    ) -> String {
        guard tokenBudget > 0, !memories.isEmpty else { return "" }
        let budgetChars = tokenBudget * approxCharsPerToken

        var lines: [String] = []
        var usedChars = header.count + 1   // header + its newline
        for memory in memories {
            let line = "- [\(memory.kind.rawValue)] \(memory.content)"
            let cost = line.count + 1       // line + newline
            if usedChars + cost > budgetChars { break }
            lines.append(line)
            usedChars += cost
        }

        guard !lines.isEmpty else { return "" }
        return ([header] + lines).joined(separator: "\n")
    }
}

extension MemoryStore {
    /// Recall for `query` and assemble the top memories into a working-context
    /// block within `tokenBudget`.
    func workingContext(for query: MemoryQuery, tokenBudget: Int = 512) -> String {
        WorkingContext.assemble(from: recall(query), tokenBudget: tokenBudget)
    }
}
