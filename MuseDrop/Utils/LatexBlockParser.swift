//
//  LatexBlockParser.swift
//  MuseDrop
//

import Foundation

enum LatexBlockParser {
    /// Extracts LaTeX suitable for Manim `MathTex` from notebook text or selection.
    static func extract(from text: String, selection: String? = nil) -> [String] {
        if let selection, let trimmed = cleaned(selection), !trimmed.isEmpty {
            return [trimmed]
        }
        
        var results: [String] = []
        results.append(contentsOf: displayMath(in: text))
        results.append(contentsOf: inlineMath(in: text))
        results.append(contentsOf: environmentBlocks(in: text))
        
        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }
    }
    
    static func primary(from text: String, selection: String? = nil) -> String? {
        extract(from: text, selection: selection).first
    }
    
    static func isLikelyMath(_ text: String) -> Bool {
        guard let cleaned = cleaned(text) else { return false }
        if cleaned.contains("\\") { return true }
        let mathChars = CharacterSet(charactersIn: "^_=+-*/∫∑√")
        return cleaned.unicodeScalars.contains { mathChars.contains($0) }
    }
    
    // MARK: - Private
    
    private static func displayMath(in text: String) -> [String] {
        patternMatches(in: text, pattern: #"\$\$([\s\S]*?)\$\$"#)
    }
    
    private static func inlineMath(in text: String) -> [String] {
        patternMatches(in: text, pattern: #"(?<!\$)\$([^$\n]+?)\$(?!\$)"#)
    }
    
    private static func environmentBlocks(in text: String) -> [String] {
        patternMatches(
            in: text,
            pattern: #"\\begin\{(equation\*?|align\*?|gather\*?)\}([\s\S]*?)\\end\{\1\}"#,
            group: 2
        )
    }
    
    private static func patternMatches(
        in text: String,
        pattern: String,
        group: Int = 1
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: text) else { return nil }
            return cleaned(String(text[capture]))
        }
    }
    
    private static func cleaned(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        
        if value.hasPrefix("$$"), value.hasSuffix("$$"), value.count > 4 {
            value = String(value.dropFirst(2).dropLast(2))
        } else if value.hasPrefix("$"), value.hasSuffix("$"), value.count > 2 {
            value = String(value.dropFirst().dropLast())
        }
        
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, isSafeForManim(value) else { return nil }
        return value
    }
    
    /// Rejects LaTeX primitives that can read/write local files or invoke the
    /// shell when compiled by the system `latex`/`pdflatex` that Manim drives.
    /// Applied to *all* LaTeX that reaches a render job, including text the user
    /// types directly into the animation studio.
    static func isSafeForManim(_ latex: String) -> Bool {
        let blocked = [
            "\\input", "\\include", "\\write", "\\openin", "\\openout",
            "\\closein", "\\closeout", "\\read", "\\immediate", "\\shell",
            "\\catcode", "\\csname", "\\special", "\\loop", "\\url{", "\\href{"
        ]
        let lower = latex.lowercased()
        return !blocked.contains { lower.contains($0) }
    }
}
