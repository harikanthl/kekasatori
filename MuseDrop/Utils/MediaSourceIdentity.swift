//
//  MediaSourceIdentity.swift
//  MuseDrop
//
//  Stable identity for matching study data to a specific video/file.
//

import Foundation

enum MediaSourceIdentity {
    /// Fingerprint used to ensure a saved transcript belongs to this library item.
    static func key(for item: DownloadItem) -> String {
        if let path = item.outputPath?.path, !path.isEmpty {
            return "file:\(path)"
        }
        let normalized = normalizeURL(item.url)
        guard !normalized.isEmpty else { return "id:\(item.id.uuidString)" }
        return "url:\(normalized)"
    }
    
    static func key(downloadURL: String, outputPath: String?) -> String {
        if let outputPath, !outputPath.isEmpty {
            return "file:\(outputPath)"
        }
        let normalized = normalizeURL(downloadURL)
        guard !normalized.isEmpty else { return "" }
        return "url:\(normalized)"
    }
    
    static func normalizeURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        if let videoID = youtubeVideoID(from: trimmed) {
            return "youtube:\(videoID)"
        }
        if let arxivId = PaperURLDetector.arxivId(from: trimmed) {
            return "arxiv:\(arxivId)"
        }
        if let pmid = PaperURLDetector.pubmedId(from: trimmed) {
            return "pubmed:\(pmid)"
        }
        
        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }
        
        components.fragment = nil
        components.queryItems = components.queryItems?.filter {
            !["si", "feature", "t", "list", "index"].contains($0.name.lowercased())
        }
        return (components.url?.absoluteString ?? trimmed).lowercased()
    }
    
    static func youtubeVideoID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            return nil
        }
        
        if host.contains("youtu.be") {
            let id = url.pathComponents.filter { $0 != "/" }.first
            return id?.isEmpty == false ? id : nil
        }
        
        guard host.contains("youtube.com") else { return nil }
        
        if url.path == "/watch", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            return items.first(where: { $0.name == "v" })?.value
        }
        
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
            return parts[1]
        }
        
        return nil
    }
    
    static func durationsAreCompatible(videoSeconds: Double?, transcriptSeconds: Double?) -> Bool {
        guard let videoSeconds, videoSeconds > 60,
              let transcriptSeconds, transcriptSeconds > 60 else {
            return true
        }
        let delta = abs(videoSeconds - transcriptSeconds)
        let tolerance = max(90.0, videoSeconds * 0.12)
        return delta <= tolerance
    }
    
    static func formatDuration(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}
