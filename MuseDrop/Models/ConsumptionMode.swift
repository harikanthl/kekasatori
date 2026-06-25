//
//  ConsumptionMode.swift
//  MuseDrop
//

import Foundation

enum ConsumptionMode: String, Codable, CaseIterable {
    case download
    case streamOnly
}

enum StreamMediaKind: String, Codable, CaseIterable {
    case audio
    case video
}

struct StreamMetadata: Codable {
    var title: String
    var thumbnailURL: URL?
    var durationSeconds: Double
    var uploader: String
    var extractor: String
}

struct ResolvedStream {
    var playbackURL: URL
    var expiresAt: Date
}
