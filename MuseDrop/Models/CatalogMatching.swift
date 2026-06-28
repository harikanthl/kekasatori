//
//  CatalogMatching.swift
//  MuseDrop
//
//  Shared word-boundary text matching used by the Methods and Tasks catalogs to
//  detect controlled-vocabulary terms in a paper's title + abstract.
//

import Foundation

enum CatalogText {
    /// Whether `needle` appears in `haystack` as a whole token (not a substring).
    /// Short tokens that carry any uppercase (LLM, GQA, RoPE, OCR, T5) are treated
    /// as acronyms/stylized names and matched **case-sensitively**, so we don't
    /// tag the ordinary words "act", "sam", or "dino" appearing in prose. Longer,
    /// lowercaseable phrases match case-insensitively.
    static func mentions(_ haystack: String, _ needle: String) -> Bool {
        guard needle.count >= 2 else { return false }
        let caseSensitive = needle.count <= 5 && needle.contains { $0.isUppercase }
        var options: NSString.CompareOptions = [.regularExpression]
        if !caseSensitive { options.insert(.caseInsensitive) }
        // Boundaries that also treat '-' as a separator, so "U-Net" / "fine-tuning"
        // match without bleeding into adjacent word characters.
        let pattern = "(?<![\\w-])" + NSRegularExpression.escapedPattern(for: needle) + "(?![\\w-])"
        return haystack.range(of: pattern, options: options) != nil
    }
}
