//
//  PaperURLDetector.swift
//  MuseDrop
//

import Foundation

enum PaperURLKind: Equatable, Sendable {
    case arxiv(id: String)
    case pubmed(pmid: String)
    case doi(String)
    case genericURL(URL)
}

enum PaperURLDetector {
    static func detect(in raw: String) -> PaperURLKind? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if let arxivId = arxivId(from: trimmed) {
            return .arxiv(id: arxivId)
        }
        if let pmid = pubmedId(from: trimmed) {
            return .pubmed(pmid: pmid)
        }
        if let doi = doi(from: trimmed) {
            return .doi(doi)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return .genericURL(url)
        }
        return nil
    }
    
    static func arxivId(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let patterns = [
            #"arxiv\.org/abs/([0-9]{4}\.[0-9]{4,5}(?:v[0-9]+)?)"#,
            #"arxiv\.org/pdf/([0-9]{4}\.[0-9]{4,5}(?:v[0-9]+)?)"#,
            #"arxiv\.org/html/([0-9]{4}\.[0-9]{4,5}(?:v[0-9]+)?)"#,
            #"^([0-9]{4}\.[0-9]{4,5}(?:v[0-9]+)?)$"#
        ]
        for pattern in patterns {
            if let id = firstCapture(pattern: pattern, in: value) {
                return stripVersion(id)
            }
        }
        return nil
    }
    
    static func pubmedId(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("pmid:") {
            let id = String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return id.allSatisfy(\.isNumber) ? id : nil
        }
        if let id = firstCapture(pattern: #"pubmed\.ncbi\.nlm\.nih\.gov/([0-9]+)"#, in: value) {
            return id
        }
        return nil
    }
    
    static func doi(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("doi:") {
            return String(value.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        if let captured = firstCapture(pattern: #"doi\.org/(10\.[^/\s]+/[^\s]+)"#, in: value) {
            return captured
        }
        if value.hasPrefix("10."), !value.contains(" ") {
            return value
        }
        return nil
    }
    
    private static func stripVersion(_ arxivId: String) -> String {
        if let range = arxivId.range(of: #"v[0-9]+$"#, options: .regularExpression) {
            return String(arxivId[..<range.lowerBound])
        }
        return arxivId
    }
    
    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }
}
