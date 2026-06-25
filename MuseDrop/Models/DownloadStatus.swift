//
//  DownloadStatus.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

enum DownloadStatus: String, Codable {
    case queued
    case downloading
    case merging
    case converting
    case completed
    case failed
}

