//
//  MediaMetadata.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

struct MediaMetadata: Codable {
    var duration: TimeInterval
    var size: Int64
    var fileType: String
    var resolution: String?
    
    init(duration: TimeInterval = 0, size: Int64 = 0, fileType: String = "", resolution: String? = nil) {
        self.duration = duration
        self.size = size
        self.fileType = fileType
        self.resolution = resolution
    }
}

