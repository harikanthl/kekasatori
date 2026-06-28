//
//  FullTextReader.swift
//  MuseDrop
//
//  DeepResearchAgent's Read stage (Phase 4). Fetches a scholarly paper's full
//  text (open-access PDF), extracts it, and returns the passages most relevant
//  to the research question via the on-device RAG index.
//
//  The index it builds per paper is EPHEMERAL — keyed by a throwaway UUID and
//  removed before returning — so reading for a research session never pollutes
//  the Library or the persistent (tutor) RAG store. Everything is best-effort:
//  a gated paper or a fetch/extract failure yields no passages, and synthesis
//  falls back to that source's abstract.
//

import Foundation

actor FullTextReader {
    static let shared = FullTextReader()

    /// Full-text excerpts for `hit` most relevant to `query`, or `[]` when the
    /// paper can't be fetched/extracted (gated, network error, image-only PDF).
    func passages(for hit: PaperHit, query: String, limit: Int) async -> [String] {
        guard let text = await fullText(for: hit), text.count > 400 else { return [] }

        let id = UUID()
        await RAGIndexService.shared.ingest(downloadId: id, text: text)
        let chunks = await RAGIndexService.shared.retrieve(downloadId: id, query: query, limit: limit)
        await RAGIndexService.shared.remove(downloadId: id)   // ephemeral — clean up
        return chunks.map(\.text).filter { !$0.isEmpty }
    }

    // MARK: - Fetch + extract

    /// Resolve a paper to a fetchable PDF and extract its text. arXiv preprints
    /// use the canonical PDF URL; otherwise the provider's open-access PDF.
    private func fullText(for hit: PaperHit) async -> String? {
        let pdfURL: URL?
        if let arxivId = hit.arxivId, !arxivId.isEmpty {
            let bare = PaperHit.normalizedArxivId(arxivId)
            pdfURL = URL(string: "https://arxiv.org/pdf/\(bare).pdf")
        } else if let pdf = hit.pdfURL, !pdf.isEmpty {
            pdfURL = URL(string: pdf)
        } else {
            pdfURL = nil
        }
        guard let url = pdfURL else { return nil }
        return await downloadAndExtract(url)
    }

    private func downloadAndExtract(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (Macintosh) Kekasatori/1.0 (Research Reader)",
                         forHTTPHeaderField: "User-Agent")

        guard let (tempURL, response) = try? await URLSession.shared.download(for: request) else {
            return nil
        }
        // PDFKit opens by path extension, so give the temp file a `.pdf` name.
        let pdfPath = tempURL.appendingPathExtension("pdf")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: pdfPath)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              (try? FileManager.default.moveItem(at: tempURL, to: pdfPath)) != nil else {
            return nil
        }

        // Text-layer extraction only (no OCR) — fast, and arXiv/OA PDFs carry a
        // text layer. Image-only scans return empty and are skipped.
        let text = PDFTextExtractor.extractText(from: pdfPath)
        return text.count > 400 ? text : nil
    }
}
