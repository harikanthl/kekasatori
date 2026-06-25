//
//  ManimAnimationStyle.swift
//  MuseDrop
//

import Foundation

enum ManimAnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case write
    case fadeIn
    case grow
    case transform
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .write: return "Write"
        case .fadeIn: return "Fade In"
        case .grow: return "Grow"
        case .transform: return "Transform"
        }
    }
    
    var subtitle: String {
        switch self {
        case .write: return "Hand-drawn reveal"
        case .fadeIn: return "Gentle appearance"
        case .grow: return "Scale from center"
        case .transform: return "Morph between forms"
        }
    }
    
    var icon: String {
        switch self {
        case .write: return "pencil.line"
        case .fadeIn: return "sun.haze"
        case .grow: return "arrow.up.left.and.arrow.down.right"
        case .transform: return "arrow.triangle.2.circlepath"
        }
    }
}

enum ManimRenderQuality: String, CaseIterable, Identifiable, Codable, Sendable {
    case draft
    case standard
    case high
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .draft: return "Draft"
        case .standard: return "Standard"
        case .high: return "High"
        }
    }
    
    var manimFlag: String {
        switch self {
        case .draft: return "-ql"
        case .standard: return "-qm"
        case .high: return "-qh"
        }
    }
}

struct NotebookAnimationRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let latex: String
    var sceneType: ManimSceneType
    let style: ManimAnimationStyle
    let quality: ManimRenderQuality
    let createdAt: Date
    let videoFileName: String
    
    init(
        id: UUID = UUID(),
        latex: String,
        sceneType: ManimSceneType = .auto,
        style: ManimAnimationStyle,
        quality: ManimRenderQuality,
        createdAt: Date = Date(),
        videoFileName: String
    ) {
        self.id = id
        self.latex = latex
        self.sceneType = sceneType
        self.style = style
        self.quality = quality
        self.createdAt = createdAt
        self.videoFileName = videoFileName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        latex = try container.decode(String.self, forKey: .latex)
        sceneType = try container.decodeIfPresent(ManimSceneType.self, forKey: .sceneType) ?? .auto
        style = try container.decode(ManimAnimationStyle.self, forKey: .style)
        quality = try container.decode(ManimRenderQuality.self, forKey: .quality)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        videoFileName = try container.decode(String.self, forKey: .videoFileName)
    }
}

struct NotebookAnimationManifest: Codable, Sendable {
    var animations: [NotebookAnimationRecord]
    
    static let empty = NotebookAnimationManifest(animations: [])
}
