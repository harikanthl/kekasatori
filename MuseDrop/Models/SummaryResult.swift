//
//  SummaryResult.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

struct SummaryResult: Codable {
    var oneLine: String
    var paragraph: String
    var bullets: [String]
    var timestamp: Date
    
    init(oneLine: String = "", paragraph: String = "", bullets: [String] = [], timestamp: Date = Date()) {
        self.oneLine = oneLine
        self.paragraph = paragraph
        self.bullets = bullets
        self.timestamp = timestamp
    }
}

