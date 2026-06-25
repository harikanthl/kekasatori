//
//  PaperMetadata.swift
//  MuseDrop
//

import Foundation

enum PaperSource: String, Codable, Sendable {
    case arxiv
    case pubmed
    case doi
    case pdf
    case web

    var displayName: String {
        switch self {
        case .arxiv: return "arXiv"
        case .pubmed: return "PubMed"
        case .doi: return "DOI"
        case .pdf: return "PDF"
        case .web: return "Web"
        }
    }
}

struct PaperMetadata: Codable, Sendable {
    var source: PaperSource
    var sourceURL: String
    var arxivId: String?
    var pubmedId: String?
    var doi: String?
    var title: String
    var authors: [String]
    var abstract: String
    var publishedAt: String?
    var htmlFileName: String?
    var pdfFileName: String
    
    static let metadataFileName = "metadata.json"
    static let defaultPDFFileName = "paper.pdf"
    static let defaultHTMLFileName = "paper.html"
    /// Extracted readable plain text for web articles (study/Tutor/RAG source).
    static let articleTextFileName = "article.txt"
}

extension DownloadItem {
    var isResearchDocument: Bool {
        let kind = format.lowercased()
        return ["arxiv", "pubmed", "doi", "pdf", "paper", "web"].contains(kind)
    }
    
    var paperBundleURL: URL? {
        guard isResearchDocument else { return nil }
        return PathUtils.paperBundleDirectory(itemId: id)
    }
    
    var paperMetadataURL: URL? {
        paperBundleURL?.appendingPathComponent(PaperMetadata.metadataFileName)
    }
}
