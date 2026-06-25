//
//  PDFTextExtractor.swift
//  MuseDrop
//

import Foundation
import PDFKit

enum PDFTextExtractor {
    static func extractText(from pdfURL: URL, maxPages: Int = 120) -> String {
        guard let document = PDFDocument(url: pdfURL) else { return "" }
        let pageCount = min(document.pageCount, maxPages)
        var parts: [String] = []
        parts.reserveCapacity(pageCount)
        
        for index in 0..<pageCount {
            guard let page = document.page(at: index), let text = page.string else { continue }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                parts.append(cleaned)
            }
        }
        return parts.joined(separator: "\n\n")
    }
    
    static func extractText(bundleURL: URL) -> String {
        let pdfURL = bundleURL.appendingPathComponent(PaperMetadata.defaultPDFFileName)
        if FileManager.default.fileExists(atPath: pdfURL.path) {
            let pdfText = extractText(from: pdfURL)
            if pdfText.count > 200 { return pdfText }
        }

        // Web articles: pre-extracted readable plain text.
        let articleURL = bundleURL.appendingPathComponent(PaperMetadata.articleTextFileName)
        if let articleText = try? String(contentsOf: articleURL, encoding: .utf8),
           articleText.count > 200 {
            return articleText
        }

        if let metadata = PaperMetadataStore.load(bundleURL: bundleURL),
           !metadata.abstract.isEmpty {
            var body = "\(metadata.title)\n\n"
            if !metadata.authors.isEmpty {
                body += metadata.authors.joined(separator: ", ") + "\n\n"
            }
            body += metadata.abstract
            return body
        }
        return ""
    }
}

enum PaperMetadataStore {
    static func load(bundleURL: URL) -> PaperMetadata? {
        let url = bundleURL.appendingPathComponent(PaperMetadata.metadataFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PaperMetadata.self, from: data)
    }
    
    static func save(_ metadata: PaperMetadata, bundleURL: URL) throws {
        let url = bundleURL.appendingPathComponent(PaperMetadata.metadataFileName)
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: url, options: .atomic)
    }
}
