//
//  SubtitleParser.swift
//  MuseDrop
//

import Foundation

enum SubtitleParser {
    /// Strips VTT/SRT timing markup and returns plain transcript text.
    static func plainText(from contents: String) -> String {
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let jsonText = plainTextFromJSON3(trimmed), jsonText.count > 80 {
                return jsonText
            }
        }
        
        var lines: [String] = []
        
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line == "WEBVTT" || line.hasPrefix("NOTE") { continue }
            if line.hasPrefix("Kind:") || line.hasPrefix("Language:") { continue }
            if line.range(of: #"^\d+$"#, options: .regularExpression) != nil { continue }
            if line.contains("-->") { continue }
            if line.hasPrefix("align:") || line.hasPrefix("position:") { continue }
            
            let cleaned = stripVTTTags(line)
            if !cleaned.isEmpty {
                lines.append(cleaned)
            }
        }
        
        var deduped: [String] = []
        for line in lines {
            if deduped.last != line {
                deduped.append(line)
            }
        }
        
        return deduped.joined(separator: " ")
    }
    
    /// YouTube `json3` / timedtext payloads.
    static func plainTextFromJSON3(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        
        var parts: [String] = []
        
        if let dict = root as? [String: Any], let events = dict["events"] as? [[String: Any]] {
            for event in events {
                guard let segs = event["segs"] as? [[String: Any]] else { continue }
                for seg in segs {
                    if let text = seg["utf8"] as? String {
                        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty { parts.append(cleaned) }
                    }
                }
            }
        }
        
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }
    
    private static func stripVTTTags(_ line: String) -> String {
        line.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
