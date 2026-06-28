//
//  PDFTextExtractor.swift
//  MuseDrop
//

import Foundation
import PDFKit
import Vision
import CoreGraphics
import ImageIO

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

    /// Per-page extraction that falls back to on-device OCR (Vision) for pages
    /// with no embedded text layer — i.e. scanned or image-only PDFs that
    /// `extractText(from:)` cannot read. Pages with a text layer use it directly.
    static func extractTextWithOCR(from pdfURL: URL, maxPages: Int = 120) async -> String {
        guard let document = PDFDocument(url: pdfURL) else { return "" }
        let pageCount = min(document.pageCount, maxPages)
        var parts: [String] = []
        parts.reserveCapacity(pageCount)

        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }

            // Prefer the embedded text layer when present (fast, exact).
            if let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                parts.append(text)
                continue
            }

            // No text layer → render the page and recognize text on-device.
            if let image = renderPageImage(page), let ocr = await ocrText(from: image) {
                let cleaned = ocr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { parts.append(cleaned) }
            }
        }
        return parts.joined(separator: "\n\n")
    }

    /// OCR-aware bundle extraction. Tries the synchronous text path first
    /// (text-layer PDF → article.txt → metadata abstract) and only falls back
    /// to the slower OCR pass when that yields too little to be useful.
    static func extractTextWithOCR(bundleURL: URL) async -> String {
        let quick = extractText(bundleURL: bundleURL)
        if quick.count > 200 { return quick }

        let pdfURL = bundleURL.appendingPathComponent(PaperMetadata.defaultPDFFileName)
        if FileManager.default.fileExists(atPath: pdfURL.path) {
            let ocr = await extractTextWithOCR(from: pdfURL)
            if ocr.count > quick.count { return ocr }
        }
        return quick
    }

    /// PNG-encodes a rendered page bitmap (for multimodal/vision LLM input).
    static func pngData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Renders a PDF page to a bitmap for OCR. `scale` oversamples the page so
    /// small body text clears Vision's minimum text-height threshold.
    static func renderPageImage(_ page: PDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// On-device text recognition via the modern Vision Swift API (macOS 15+).
    private static func ocrText(from cgImage: CGImage) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            let observations = try await request.perform(on: cgImage)
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        } catch {
            return nil
        }
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
