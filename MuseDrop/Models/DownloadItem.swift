//
//  DownloadItem.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

struct DownloadItem: Identifiable, Codable {
    let id: UUID
    var url: String
    var title: String
    var thumbnail: URL?
    var format: String
    var progress: Double
    var status: DownloadStatus
    var outputPath: URL?
    var createdDate: Date
    var summaryExists: Bool
    var errorMessage: String?
    
    var consumptionMode: ConsumptionMode
    var streamURL: URL?
    var streamExpiresAt: Date?
    var streamMediaKind: StreamMediaKind?
    var durationSeconds: Double?

    /// Playlist collection this item was imported as part of (nil for singles).
    var playlistId: UUID?
    var playlistTitle: String?

    init(
        id: UUID = UUID(),
        url: String,
        title: String = "",
        thumbnail: URL? = nil,
        format: String = "",
        progress: Double = 0.0,
        status: DownloadStatus = .queued,
        outputPath: URL? = nil,
        createdDate: Date = Date(),
        summaryExists: Bool = false,
        errorMessage: String? = nil,
        consumptionMode: ConsumptionMode = .download,
        streamURL: URL? = nil,
        streamExpiresAt: Date? = nil,
        streamMediaKind: StreamMediaKind? = nil,
        durationSeconds: Double? = nil,
        playlistId: UUID? = nil,
        playlistTitle: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.thumbnail = thumbnail
        self.format = format
        self.progress = progress
        self.status = status
        self.outputPath = outputPath
        self.createdDate = createdDate
        self.summaryExists = summaryExists
        self.errorMessage = errorMessage
        self.consumptionMode = consumptionMode
        self.streamURL = streamURL
        self.streamExpiresAt = streamExpiresAt
        self.streamMediaKind = streamMediaKind
        self.durationSeconds = durationSeconds
        self.playlistId = playlistId
        self.playlistTitle = playlistTitle
    }
}

extension DownloadItem {
    var isStreamOnly: Bool {
        consumptionMode == .streamOnly
    }
    
    var isPlayable: Bool {
        if isResearchDocument {
            return outputPath != nil || FileManager.default.fileExists(atPath: PathUtils.paperBundleDirectory(itemId: id).path)
        }
        if let outputPath {
            return FileManager.default.fileExists(atPath: outputPath.path)
        }
        return isStreamOnly && streamURL != nil
    }
    
    var displayTitle: String {
        if !title.isEmpty { return title }
        switch status {
        case .completed: return isStreamOnly ? "Stream" : "Untitled Download"
        case .failed: return "Failed Download"
        case .queued: return "Queued Download"
        case .downloading, .merging, .converting: return "Downloading…"
        }
    }
    
    var displayFormat: String {
        if isStreamOnly {
            return (streamMediaKind?.rawValue ?? format).uppercased()
        }
        if !format.isEmpty { return format.uppercased() }
        if let ext = outputPath?.pathExtension, !ext.isEmpty { return ext.uppercased() }
        return "MEDIA"
    }
    
    var isAudioMedia: Bool {
        if isStreamOnly {
            return streamMediaKind == .audio
        }
        let ext = outputPath?.pathExtension.lowercased() ?? ""
        return ["mp3", "m4a", "aac", "wav", "flac", "ogg"].contains(ext)
    }

    /// A generated two-host podcast (gets a compact, focused player window).
    var isPodcast: Bool {
        format.caseInsensitiveCompare("Podcast") == .orderedSame || url.hasPrefix("podcast://")
    }
    
    var streamURLIsExpired: Bool {
        guard let streamExpiresAt else { return true }
        return Date() >= streamExpiresAt
    }
}
