//
//  PaperEnrichmentService.swift
//  MuseDrop
//
//  Extracts data that plain text extraction misses — tables and the data inside
//  figures/charts/graphs — and returns it as text to append to a paper's source
//  before RAG indexing.
//
//  Two passes, each gated independently:
//    • Tables (on-device, macOS 26+): Vision RecognizeDocumentsRequest → Markdown.
//    • Figures/graphs (cloud, opt-in): page image → vision-capable LLM → data.
//
//  Runs lazily on first open and caches the result to the paper bundle, so the
//  (potentially paid, image-heavy) work happens once per paper.
//

import Foundation
import PDFKit

actor PaperEnrichmentService {
    static let shared = PaperEnrichmentService()
    private init() {}

    private static let cacheFileName = "enrichment.txt"
    private static let maxCandidatePages = 16
    private static let maxScannedPages = 120

    /// Caption markers that flag a page as likely containing a figure or table.
    private static let captionRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(figure|fig\.?|table|chart|graph|plot|scheme|diagram|exhibit)\s*\.?\s*\d"#
    )

    /// Returns `base` plus any extracted figure/table data appended. No-op (returns
    /// `base` unchanged) when nothing is enabled or nothing is found.
    func appended(to base: String, bundleURL: URL, settings: LLMProviderSettings) async -> String {
        let extra = await enrich(bundleURL: bundleURL, settings: settings)
        return extra.isEmpty ? base : base + "\n\n" + extra
    }

    /// Structured figure/table text for a paper. Cached on disk; computed once.
    func enrich(bundleURL: URL, settings: LLMProviderSettings) async -> String {
        let cacheURL = bundleURL.appendingPathComponent(Self.cacheFileName)
        if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
            return cached
        }

        let analyzeFigures = LLMRouter.shared.canAnalyzeFigures(settings: settings)
        let nativeTables: Bool = {
            if #available(macOS 26.0, *) { return true }
            return false
        }()
        // Nothing to do — don't even open the PDF.
        guard analyzeFigures || nativeTables else { return "" }

        let pdfURL = bundleURL.appendingPathComponent(PaperMetadata.defaultPDFFileName)
        guard FileManager.default.fileExists(atPath: pdfURL.path),
              let document = PDFDocument(url: pdfURL) else { return "" }

        let candidates = candidatePages(in: document)
        var blocks: [String] = []
        for index in candidates {
            guard let page = document.page(at: index),
                  let image = PDFTextExtractor.renderPageImage(page) else { continue }

            var pageBlocks: [String] = []

            if #available(macOS 26.0, *) {
                let tables = await DocumentStructureExtractor.tablesMarkdown(from: image)
                if !tables.isEmpty { pageBlocks.append(tables) }
            }

            if analyzeFigures, let png = PDFTextExtractor.pngData(from: image),
               let figure = await analyzeFigure(png: png, page: index + 1, settings: settings) {
                pageBlocks.append(figure)
            }

            if !pageBlocks.isEmpty {
                blocks.append("### Page \(index + 1) — figures & tables\n\n"
                    + pageBlocks.joined(separator: "\n\n"))
            }
        }

        let combined = blocks.isEmpty
            ? ""
            : "## Extracted figure & table data\n\n" + blocks.joined(separator: "\n\n")
        // Cache even when empty so we don't re-scan a paper with no figures.
        try? combined.write(to: cacheURL, atomically: true, encoding: .utf8)
        return combined
    }

    // MARK: - Candidate selection

    /// Pages worth the expensive image pass: those with a figure/table caption,
    /// or sparse text (image-dominated). Capped to bound cost on long papers.
    private func candidatePages(in document: PDFDocument) -> [Int] {
        var pages: [Int] = []
        let pageCount = min(document.pageCount, Self.maxScannedPages)
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            let range = NSRange(text.startIndex..., in: text)
            let hasCaption = Self.captionRegex.firstMatch(in: text, range: range) != nil
            let sparse = text.trimmingCharacters(in: .whitespacesAndNewlines).count < 120
            if hasCaption || sparse {
                pages.append(index)
                if pages.count >= Self.maxCandidatePages { break }
            }
        }
        return pages
    }

    // MARK: - Figure analysis (cloud, multimodal)

    private func analyzeFigure(png: Data, page: Int, settings: LLMProviderSettings) async -> String? {
        let prompt = """
        This is page \(page) of an academic paper. Extract every figure, chart, graph, plot, \
        and table on the page as structured text, so it can be analysed without seeing the image.

        For each figure/chart/graph: state its label (e.g. "Figure 3"), what it shows, the axes \
        and their units, and list the approximate data values, series, and trends you can read off it. \
        For each table: reproduce it as a GitHub-flavoured Markdown table. \
        If the page contains no figures, charts, graphs, or tables, reply with exactly "NONE". \
        Do not add commentary beyond the extracted data.
        """
        let message = LLMMessage(.user, prompt, images: [png])
        guard let result = try? await LLMRouter.shared.cloudComplete(messages: [message], settings: settings) else {
            return nil
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "NONE" else { return nil }
        return trimmed
    }
}
