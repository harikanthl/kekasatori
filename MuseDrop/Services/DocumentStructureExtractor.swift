//
//  DocumentStructureExtractor.swift
//  MuseDrop
//
//  On-device table/structure recognition via Vision's RecognizeDocumentsRequest
//  (macOS 26+). Serializes detected tables to Markdown so they can be fed into
//  the same text → chunk → RAG pipeline as everything else. No network.
//

import Foundation
import Vision

@available(macOS 26.0, *)
enum DocumentStructureExtractor {
    /// Recognizes tables on a page image and serializes them to Markdown.
    /// Returns "" when no tables are detected.
    static func tablesMarkdown(from cgImage: CGImage) async -> String {
        let request = RecognizeDocumentsRequest()
        guard let observations = try? await request.perform(on: cgImage) else { return "" }

        var blocks: [String] = []
        for observation in observations {
            for table in observation.document.tables {
                if let markdown = markdown(for: table) {
                    blocks.append(markdown)
                }
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func markdown(for table: DocumentObservation.Container.Table) -> String? {
        let rows = table.rows
        guard !rows.isEmpty else { return nil }

        let header = rows[0].map(cellText)
        guard !header.isEmpty else { return nil }

        var lines: [String] = []
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append("| " + row.map(cellText).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    private static func cellText(_ cell: DocumentObservation.Container.Table.Cell) -> String {
        cell.content.text.transcript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespaces)
    }
}
