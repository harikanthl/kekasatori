//
//  MarkdownMessageView.swift
//  MuseDrop
//
//  Lightweight, dependency-free Markdown renderer for tutor chat replies.
//  Block-level parsing (headings, lists, fenced code, quotes, rules) is done
//  here; inline formatting (bold/italic/inline-code/links) is delegated to
//  Foundation's AttributedString markdown parser. Designed to render safely on
//  partial/streaming input — malformed or unclosed markdown degrades to text
//  rather than throwing.
//

import SwiftUI

struct MarkdownMessageView: View {
    let text: String

    private var blocks: [MarkdownBlock] { MarkdownParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let raw):
            Text(MarkdownParser.inline(raw))
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let raw):
            Text(MarkdownParser.inline(raw))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

        case .bulleted(let items):
            listView(items.map { (marker: "•", text: $0) })

        case .numbered(let items):
            listView(items.map { (marker: "\($0.number).", text: $0.text) })

        case .code(let language, let code):
            codeBlock(language: language, code: code)

        case .quote(let raw):
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 3)
                Text(MarkdownParser.inline(raw))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .rule:
            Divider().padding(.vertical, 2)
        }
    }

    private func listView(_ rows: [(marker: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(row.marker)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(MarkdownParser.inline(row.text))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func codeBlock(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.top, Theme.Spacing.xs)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(.separator.opacity(0.5))
        )
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.weight(.bold)
        case 2: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }
}

// MARK: - Parsing

private struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bulleted([String])
        case numbered([(number: Int, text: String)])
        case code(language: String?, code: String)
        case quote(String)
        case rule
    }
}

private enum MarkdownParser {
    /// Inline formatting via Foundation's markdown parser. Falls back to plain
    /// text if the (possibly mid-stream) fragment fails to parse.
    static func inline(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        var paragraphBuffer: [String] = []
        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            blocks.append(MarkdownBlock(kind: .paragraph(joined)))
            paragraphBuffer.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let inner = lines[i].trimmingCharacters(in: .whitespaces)
                    if inner.hasPrefix("```") { break }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(MarkdownBlock(
                    kind: .code(language: language.isEmpty ? nil : language,
                                code: codeLines.joined(separator: "\n"))
                ))
                i += 1   // consume closing fence (no-op if we hit end of input)
                continue
            }

            // Blank line ends the current paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .rule))
                i += 1
                continue
            }

            // ATX heading.
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
                i += 1
                continue
            }

            // Unordered list (collect consecutive items).
            if let firstItem = parseBullet(trimmed) {
                flushParagraph()
                var items = [firstItem]
                i += 1
                while i < lines.count,
                      let next = parseBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    i += 1
                }
                blocks.append(MarkdownBlock(kind: .bulleted(items)))
                continue
            }

            // Ordered list (collect consecutive items).
            if let firstItem = parseNumbered(trimmed) {
                flushParagraph()
                var items = [firstItem]
                i += 1
                while i < lines.count,
                      let next = parseNumbered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    i += 1
                }
                blocks.append(MarkdownBlock(kind: .numbered(items)))
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(MarkdownBlock(kind: .quote(content)))
                i += 1
                continue
            }

            // Default: accumulate into the current paragraph.
            paragraphBuffer.append(trimmed)
            i += 1
        }

        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func parseBullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func parseNumbered(_ line: String) -> (number: Int, text: String)? {
        var digits = ""
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber {
            digits.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !digits.isEmpty, let number = Int(digits), idx < line.endIndex else { return nil }
        // Accept "1." or "1)" followed by a space.
        guard line[idx] == "." || line[idx] == ")" else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        return (number, text)
    }
}
