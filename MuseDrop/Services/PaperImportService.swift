//
//  PaperImportService.swift
//  MuseDrop
//

import Foundation

enum PaperImportError: LocalizedError {
    case invalidInput
    case unsupportedURL
    case metadataUnavailable
    case downloadFailed(String)
    case fileCopyFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Enter an arXiv, PubMed, DOI, or PDF link."
        case .unsupportedURL: return "This link is not a supported research paper source."
        case .metadataUnavailable: return "Could not fetch paper metadata."
        case .downloadFailed(let detail): return "Paper download failed: \(detail)"
        case .fileCopyFailed: return "Could not save the paper to your library."
        }
    }
}

@MainActor
final class PaperImportService {
    static let shared = PaperImportService()
    
    private let libraryManager = LibraryManager.shared
    private let logService = LogService.shared
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = ["User-Agent": "Kekasatori/1.0 (Research Reader)"]
        session = URLSession(configuration: config)
    }
    
    func importFromURL(_ raw: String) async throws -> DownloadItem {
        guard let kind = PaperURLDetector.detect(in: raw) else {
            throw PaperImportError.invalidInput
        }
        
        switch kind {
        case .arxiv(let id):
            return try await importArxiv(id: id, sourceURL: normalizedArxivURL(id))
        case .pubmed(let pmid):
            return try await importPubMed(pmid: pmid)
        case .doi(let value):
            let resolved = try await resolveDOI(value)
            return try await importFromURL(resolved)
        case .genericURL(let url):
            if let arxivId = PaperURLDetector.arxivId(from: url.absoluteString) {
                return try await importArxiv(id: arxivId, sourceURL: url.absoluteString)
            }
            if let pmid = PaperURLDetector.pubmedId(from: url.absoluteString) {
                return try await importPubMed(pmid: pmid)
            }
            // Any other web page: import as a readable article (crawling chapters
            // for multi-chapter books/docs sites).
            return try await importWebArticle(from: url)
        }
    }
    
    func importLocalPDF(from sourceURL: URL) async throws -> DownloadItem {
        let itemId = UUID()
        let bundle = PathUtils.paperBundleDirectory(itemId: itemId)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        
        let pdfDest = bundle.appendingPathComponent(PaperMetadata.defaultPDFFileName)
        if sourceURL.isFileURL {
            if FileManager.default.fileExists(atPath: pdfDest.path) {
                try FileManager.default.removeItem(at: pdfDest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: pdfDest)
        } else {
            try await download(url: sourceURL, to: pdfDest)
        }
        
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let metadata = PaperMetadata(
            source: .pdf,
            sourceURL: sourceURL.absoluteString,
            title: title.isEmpty ? "Imported PDF" : title,
            authors: [],
            abstract: "",
            pdfFileName: PaperMetadata.defaultPDFFileName
        )
        try PaperMetadataStore.save(metadata, bundleURL: bundle)
        
        return persistItem(
            id: itemId,
            url: sourceURL.absoluteString,
            title: metadata.title,
            format: PaperSource.pdf.rawValue,
            outputPath: pdfDest
        )
    }
    
    // MARK: - Web articles / books

    /// Import any web page as a readable article. If it looks like a multi-chapter
    /// book/docs site, crawl same-origin chapter links and combine them into one
    /// studyable document. Stored as an offline snapshot in a paper bundle.
    func importWebArticle(from url: URL) async throws -> DownloadItem {
        let landingHTML = try await fetchHTML(url)
        let landing = await extractOffMain(html: landingHTML)
        let host = url.host ?? "web"

        let chapterURLs = ArticleExtractor.chapterLinks(html: landingHTML, base: url)
        var sections: [(title: String, text: String)] = []
        var totalChars = 0

        if chapterURLs.count >= 3 {
            // The landing page is often a table of contents; include it only if substantial.
            if landing.text.count > 600 {
                sections.append((landing.title, landing.text))
                totalChars += landing.text.count
            }
            for chapterURL in chapterURLs.prefix(50) {
                if totalChars > 1_500_000 { break }
                guard let chapterHTML = try? await fetchHTML(chapterURL) else { continue }
                let chapter = await extractOffMain(html: chapterHTML)
                guard chapter.text.count > 200 else { continue }
                sections.append((chapter.title, chapter.text))
                totalChars += chapter.text.count
            }
        }

        if sections.count < 3 {
            // Single article.
            sections = [(landing.title, landing.text)]
        }

        guard sections.contains(where: { $0.text.count > 200 }) else {
            throw PaperImportError.downloadFailed("Couldn't extract readable text from \(url.absoluteString)")
        }

        let isBook = sections.count >= 3
        let title = landing.title.isEmpty ? host : landing.title
        let plainText = sections
            .map { $0.title.isEmpty ? $0.text : "## \($0.title)\n\n\($0.text)" }
            .joined(separator: "\n\n")
        let excerpt = String((sections.first(where: { $0.text.count > 100 })?.text ?? "").prefix(320))

        let itemId = UUID()
        let bundle = PathUtils.paperBundleDirectory(itemId: itemId)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let htmlURL = bundle.appendingPathComponent(PaperMetadata.defaultHTMLFileName)
        try buildReadableHTML(title: title, source: url, sections: sections)
            .write(to: htmlURL, atomically: true, encoding: .utf8)

        let textURL = bundle.appendingPathComponent(PaperMetadata.articleTextFileName)
        try plainText.write(to: textURL, atomically: true, encoding: .utf8)

        let metadata = PaperMetadata(
            source: .web,
            sourceURL: url.absoluteString,
            title: title,
            authors: [host],
            abstract: excerpt,
            htmlFileName: PaperMetadata.defaultHTMLFileName,
            pdfFileName: ""
        )
        try PaperMetadataStore.save(metadata, bundleURL: bundle)
        logService.info("Imported web \(isBook ? "book (\(sections.count) sections)" : "article"): \(title)")

        let item = persistItem(
            id: itemId,
            url: url.absoluteString,
            title: title,
            format: PaperSource.web.rawValue,
            outputPath: htmlURL
        )

        // Warm the Tutor's RAG index so chat is grounded immediately.
        let ragText = plainText
        Task.detached { await RAGIndexService.shared.ingest(downloadId: itemId, text: ragText) }
        return item
    }

    /// Run the regex-heavy extraction off the main thread to keep the UI responsive.
    private func extractOffMain(html: String) async -> ArticleExtractor.Article {
        await Task.detached(priority: .userInitiated) {
            ArticleExtractor.extract(html: html)
        }.value
    }

    private func fetchHTML(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh) Kekasatori/1.0 (Research Reader)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PaperImportError.downloadFailed("HTTP error for \(url.absoluteString)")
        }
        // Decode the (up to 6 MB) body off the main actor — this service is
        // @MainActor, and decoding a large body inline would block the UI.
        let capped = data.count > 6_000_000 ? Data(data.prefix(6_000_000)) : data
        return await Task.detached(priority: .userInitiated) {
            if let utf8 = String(data: capped, encoding: .utf8) { return utf8 }
            return String(decoding: capped, as: UTF8.self)
        }.value
    }

    private func buildReadableHTML(title: String, source: URL, sections: [(title: String, text: String)]) -> String {
        let css = """
        body{font-family:-apple-system,system-ui,Georgia,serif;max-width:760px;margin:40px auto;padding:0 24px;line-height:1.65;color:#1a1a1a;font-size:17px}
        h1{font-size:1.8rem;line-height:1.25}h2{font-size:1.3rem;margin-top:2.2rem;border-top:1px solid #eee;padding-top:1.4rem}
        .meta{color:#666;font-size:.9rem;margin:.4rem 0 2rem}.content{white-space:pre-wrap}a{color:#0a6cff;text-decoration:none}
        @media(prefers-color-scheme:dark){body{background:#1e1e1e;color:#e4e4e4}h2{border-color:#333}.meta{color:#999}}
        """
        var bodyHTML = "<h1>\(escapeHTML(title))</h1>"
        bodyHTML += "<div class=\"meta\">Saved from <a href=\"\(escapeHTML(source.absoluteString))\">\(escapeHTML(source.host ?? source.absoluteString))</a></div>"
        let multi = sections.count > 1
        for section in sections {
            if multi, !section.title.isEmpty {
                bodyHTML += "<h2>\(escapeHTML(section.title))</h2>"
            }
            bodyHTML += "<div class=\"content\">\(escapeHTML(section.text))</div>"
        }
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>\(escapeHTML(title))</title><style>\(css)</style></head><body>\(bodyHTML)</body></html>"
    }

    // MARK: - arXiv

    private func importArxiv(id: String, sourceURL: String) async throws -> DownloadItem {
        let meta = try await fetchArxivMetadata(id: id)
        let itemId = UUID()
        let bundle = PathUtils.paperBundleDirectory(itemId: itemId)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        
        guard let pdfURL = URL(string: "https://arxiv.org/pdf/\(id).pdf") else {
            throw PaperImportError.unsupportedURL
        }
        let pdfDest = bundle.appendingPathComponent(PaperMetadata.defaultPDFFileName)
        try await download(url: pdfURL, to: pdfDest)
        
        var htmlFileName: String?
        if let html = try? await fetchArxivHTML(id: id) {
            let htmlDest = bundle.appendingPathComponent(PaperMetadata.defaultHTMLFileName)
            try html.write(to: htmlDest, atomically: true, encoding: .utf8)
            htmlFileName = PaperMetadata.defaultHTMLFileName
        }
        
        let metadata = PaperMetadata(
            source: .arxiv,
            sourceURL: sourceURL,
            arxivId: id,
            title: meta.title,
            authors: meta.authors,
            abstract: meta.abstract,
            publishedAt: meta.published,
            htmlFileName: htmlFileName,
            pdfFileName: PaperMetadata.defaultPDFFileName
        )
        try PaperMetadataStore.save(metadata, bundleURL: bundle)
        
        logService.info("Imported arXiv paper \(id): \(meta.title)")
        return persistItem(
            id: itemId,
            url: sourceURL,
            title: meta.title,
            format: PaperSource.arxiv.rawValue,
            outputPath: pdfDest
        )
    }
    
    private struct ArxivMeta {
        let title: String
        let authors: [String]
        let abstract: String
        let published: String?
    }
    
    private func fetchArxivMetadata(id: String) async throws -> ArxivMeta {
        guard let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(id)") else {
            throw PaperImportError.metadataUnavailable
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8) else {
            throw PaperImportError.metadataUnavailable
        }
        
        // Scope to the <entry> element so we read the paper's title/summary rather
        // than the feed-level <title> ("ArXiv Query: …").
        let entryXML = xmlTag("entry", in: xml) ?? xml

        let title = xmlTag("title", in: entryXML)?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "arXiv:\(id)"
        let abstract = xmlTag("summary", in: entryXML)?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let published = xmlTag("published", in: entryXML)
        let authors = xmlAllTags("name", in: entryXML)
        
        return ArxivMeta(title: title, authors: authors, abstract: abstract, published: published)
    }
    
    private func fetchArxivHTML(id: String) async throws -> String {
        let candidates = [
            "https://arxiv.org/html/\(id)",
            "https://ar5iv.labs.arxiv.org/html/\(id)"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8),
                  html.lowercased().contains("<body") else { continue }
            return html
        }
        throw PaperImportError.metadataUnavailable
    }
    
    // MARK: - PubMed
    
    private func importPubMed(pmid: String) async throws -> DownloadItem {
        let meta = try await fetchPubMedMetadata(pmid: pmid)
        let itemId = UUID()
        let bundle = PathUtils.paperBundleDirectory(itemId: itemId)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        
        let sourceURL = "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/"
        var pdfDest: URL?
        
        if let pmcPDF = meta.pmcPDFURL {
            let dest = bundle.appendingPathComponent(PaperMetadata.defaultPDFFileName)
            if (try? await download(url: pmcPDF, to: dest)) != nil {
                pdfDest = dest
            }
        }
        
        var htmlFileName: String?
        if pdfDest == nil {
            let html = makePubMedHTMLPage(metadata: meta, pmid: pmid)
            let htmlDest = bundle.appendingPathComponent(PaperMetadata.defaultHTMLFileName)
            try html.write(to: htmlDest, atomically: true, encoding: .utf8)
            htmlFileName = PaperMetadata.defaultHTMLFileName
            pdfDest = htmlDest
        }
        
        let metadata = PaperMetadata(
            source: .pubmed,
            sourceURL: sourceURL,
            pubmedId: pmid,
            doi: meta.doi,
            title: meta.title,
            authors: meta.authors,
            abstract: meta.abstract,
            publishedAt: meta.published,
            htmlFileName: htmlFileName,
            pdfFileName: PaperMetadata.defaultPDFFileName
        )
        try PaperMetadataStore.save(metadata, bundleURL: bundle)
        
        logService.info("Imported PubMed paper \(pmid): \(meta.title)")
        guard let outputPath = pdfDest else {
            throw PaperImportError.fileCopyFailed
        }
        return persistItem(
            id: itemId,
            url: sourceURL,
            title: meta.title,
            format: PaperSource.pubmed.rawValue,
            outputPath: outputPath
        )
    }
    
    private struct PubMedMeta {
        let title: String
        let authors: [String]
        let abstract: String
        let published: String?
        let doi: String?
        let pmcPDFURL: URL?
    }
    
    private func fetchPubMedMetadata(pmid: String) async throws -> PubMedMeta {
        guard let summaryURL = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=\(pmid)&retmode=json") else {
            throw PaperImportError.metadataUnavailable
        }
        let (data, _) = try await session.data(from: summaryURL)
        
        struct SummaryRoot: Decodable {
            struct Result: Decodable {
                struct Author: Decodable { let name: String? }
                struct ArticleID: Decodable { let idtype: String?; let value: String? }
                let uid: String?
                let title: String?
                let pubdate: String?
                let authors: [Author]?
                let articleids: [ArticleID]?
            }
            let result: [String: Result]?
        }
        
        let decoded = try JSONDecoder().decode(SummaryRoot.self, from: data)
        guard let article = decoded.result?[pmid] else {
            throw PaperImportError.metadataUnavailable
        }
        
        let abstract = try await fetchPubMedAbstract(pmid: pmid)
        let doi = article.articleids?.first(where: { $0.idtype?.lowercased() == "doi" })?.value
        let pmc = article.articleids?.first(where: { $0.idtype?.lowercased() == "pmc" })?.value
        let pmcPDF = pmc.flatMap { URL(string: "https://www.ncbi.nlm.nih.gov/pmc/articles/\($0)/pdf/") }
        
        return PubMedMeta(
            title: article.title ?? "PubMed \(pmid)",
            authors: article.authors?.compactMap(\.name) ?? [],
            abstract: abstract,
            published: article.pubdate,
            doi: doi,
            pmcPDFURL: pmcPDF
        )
    }
    
    private func fetchPubMedAbstract(pmid: String) async throws -> String {
        guard let url = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=\(pmid)&retmode=text&rettype=abstract") else {
            throw PaperImportError.metadataUnavailable
        }
        let (data, _) = try await session.data(from: url)
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private func makePubMedHTMLPage(metadata: PubMedMeta, pmid: String) -> String {
        let authors = metadata.authors.joined(separator: ", ")
        let body = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(escapeHTML(metadata.title))</title>
        <style>body{font-family:-apple-system,system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 20px;line-height:1.55;color:#111}
        h1{font-size:1.6rem} .meta{color:#555;font-size:.95rem;margin-bottom:1.5rem} p{white-space:pre-wrap}</style></head>
        <body><h1>\(escapeHTML(metadata.title))</h1>
        <div class="meta">PubMed: \(pmid)\(metadata.published.map { " · \($0)" } ?? "")<br>\(escapeHTML(authors))</div>
        <p>\(escapeHTML(metadata.abstract))</p></body></html>
        """
        return body
    }
    
    // MARK: - Helpers
    
    private func resolveDOI(_ doi: String) async throws -> String {
        let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi
        guard let doiURL = URL(string: "https://doi.org/\(encodedDOI)") else {
            throw PaperImportError.unsupportedURL
        }
        var request = URLRequest(url: doiURL)
        request.httpMethod = "HEAD"

        // Use a session whose delegate blocks redirects to non-https / private hosts
        // (SSRF guard) and caps the redirect chain.
        let delegate = RedirectGuardDelegate()
        let guardedSession = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { guardedSession.finishTasksAndInvalidate() }

        let (_, response) = try await guardedSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url,
              let location = http.url?.absoluteString else {
            throw PaperImportError.unsupportedURL
        }
        // Final-destination validation in case no redirect callback fired.
        guard Self.isAllowedRedirectTarget(finalURL) else {
            throw PaperImportError.unsupportedURL
        }
        return location
    }

    /// Allows only https URLs whose host is not loopback/link-local/private.
    nonisolated fileprivate static func isAllowedRedirectTarget(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return !isPrivateHost(host)
    }

    nonisolated private static func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") { return true }

        // Bracketed/raw IPv6 loopback / link-local.
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return true
        }

        // IPv4 private / loopback / link-local ranges.
        let octets = host.split(separator: ".")
        if octets.count == 4, let a = Int(octets[0]), let b = Int(octets[1]) {
            if a == 127 { return true }            // loopback
            if a == 10 { return true }             // 10.0.0.0/8
            if a == 169 && b == 254 { return true } // link-local
            if a == 192 && b == 168 { return true } // 192.168.0.0/16
            if a == 172 && (16...31).contains(b) { return true } // 172.16.0.0/12
            if a == 0 { return true }
        }
        return false
    }
    
    private func download(url: URL, to destination: URL) async throws {
        let (temp, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PaperImportError.downloadFailed("HTTP error for \(url.absoluteString)")
        }
        // For PDF destinations, verify the bytes are actually a PDF (magic "%PDF-")
        // before accepting them — guards against HTML error pages / paywalls.
        if destination.pathExtension.lowercased() == "pdf" {
            guard let handle = try? FileHandle(forReadingFrom: temp) else {
                throw PaperImportError.downloadFailed("Could not read downloaded file from \(url.absoluteString)")
            }
            let header = handle.readData(ofLength: 5)
            try? handle.close()
            guard header.starts(with: Array("%PDF-".utf8)) else {
                try? FileManager.default.removeItem(at: temp)
                throw PaperImportError.downloadFailed("Downloaded file is not a PDF: \(url.absoluteString)")
            }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temp, to: destination)
    }
    
    private func persistItem(id: UUID, url: String, title: String, format: String, outputPath: URL) -> DownloadItem {
        let item = DownloadItem(
            id: id,
            url: url,
            title: title,
            format: format,
            progress: 1,
            status: .completed,
            outputPath: outputPath,
            consumptionMode: .download
        )
        libraryManager.addDownload(item)
        return item
    }
    
    private func normalizedArxivURL(_ id: String) -> String {
        "https://arxiv.org/abs/\(id)"
    }
    
    private func xmlTag(_ tag: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else {
            return nil
        }
        return String(xml[start.upperBound..<end.lowerBound])
    }
    
    private func xmlAllTags(_ tag: String, in xml: String) -> [String] {
        var results: [String] = []
        var search = xml[...]
        while let start = search.range(of: "<\(tag)>"),
              let end = search.range(of: "</\(tag)>", range: start.upperBound..<search.endIndex) {
            results.append(String(search[start.upperBound..<end.lowerBound]))
            search = search[end.upperBound...]
        }
        return results
    }
    
    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

/// Blocks HTTP redirects to non-https schemes or private/link-local hosts (SSRF
/// guard) and caps the number of redirects followed.
private final class RedirectGuardDelegate: NSObject, URLSessionTaskDelegate {
    private let maxRedirects = 10
    private var redirectCount = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        guard redirectCount <= maxRedirects,
              let url = request.url,
              PaperImportService.isAllowedRedirectTarget(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
