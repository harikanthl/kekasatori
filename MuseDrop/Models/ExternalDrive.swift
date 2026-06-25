//
//  ExternalDrive.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

struct ExternalDrive: Identifiable, Codable {
    let id: UUID
    var name: String
    var path: URL
    var availableSpace: Int64
    var totalSpace: Int64
    var isDefaultTarget: Bool
    
    init(id: UUID = UUID(), name: String, path: URL, availableSpace: Int64 = 0, totalSpace: Int64 = 0, isDefaultTarget: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.availableSpace = availableSpace
        self.totalSpace = totalSpace
        self.isDefaultTarget = isDefaultTarget
    }
}

