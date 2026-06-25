//
//  CanvasBoard.swift
//  MuseDrop
//

import Foundation

enum CanvasBoardKind: String, Codable, CaseIterable, Identifiable {
    case overview = "overview"
    case deepDive = "deep_dive"
    case questions = "questions"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var defaultTitle: String {
        switch self {
        case .overview: return "Overview"
        case .deepDive: return "Deep Dive"
        case .questions: return "Questions"
        case .custom: return "Board"
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .overview: return 0
        case .deepDive: return 1
        case .questions: return 2
        case .custom: return 99
        }
    }
}

struct CanvasBoard: Identifiable, Hashable, Sendable {
    var id: UUID
    var downloadId: UUID
    var title: String
    var kind: CanvasBoardKind
    var sortOrder: Int
    var updatedAt: Date
    var createdAt: Date
    var hasThumbnail: Bool
    
    init(
        id: UUID = UUID(),
        downloadId: UUID,
        title: String,
        kind: CanvasBoardKind,
        sortOrder: Int? = nil,
        updatedAt: Date = Date(),
        createdAt: Date = Date(),
        hasThumbnail: Bool = false
    ) {
        self.id = id
        self.downloadId = downloadId
        self.title = title
        self.kind = kind
        self.sortOrder = sortOrder ?? kind.sortOrder
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.hasThumbnail = hasThumbnail
    }
}

struct CanvasScenePayload: Codable, Sendable {
    var sceneJSON: String
    var embeddedFiles: [CanvasEmbeddedFile]
}

struct CanvasEmbeddedFile: Codable, Sendable, Identifiable {
    var id: String
    var mimeType: String
    var relativePath: String
}

/// Lightweight element batch for agent / study-pack import.
struct CanvasElementBatch: Codable, Sendable {
    var elements: [[String: AnyCodableValue]]
    
    static func textBlocks(
        texts: [String],
        startX: Double = 80,
        startY: Double = 80,
        accentHex: String = "#ff6b9d"
    ) -> CanvasElementBatch {
        var elements: [[String: AnyCodableValue]] = []
        var y = startY
        for (index, text) in texts.enumerated() {
            let id = UUID().uuidString
            elements.append([
                "type": .string("text"),
                "id": .string(id),
                "x": .double(startX),
                "y": .double(y),
                "width": .double(320),
                "height": .double(48),
                "text": .string(text),
                "fontSize": .double(20),
                "strokeColor": .string("#1e1e1e"),
                "backgroundColor": .string("transparent"),
                "fillStyle": .string("solid"),
                "strokeWidth": .double(1),
                "roughness": .double(1),
                "opacity": .double(100),
                "angle": .double(0),
                "seed": .double(Double(index + 1)),
                "version": .double(1),
                "versionNonce": .double(Double.random(in: 1...9_999_999)),
                "isDeleted": .bool(false),
                "groupIds": .array([]),
                "boundElements": .null,
                "updated": .double(Date().timeIntervalSince1970 * 1000),
                "link": .null,
                "locked": .bool(false),
            ])
            y += 72
        }
        _ = accentHex
        return CanvasElementBatch(elements: elements)
    }
}

enum AnyCodableValue: Codable, Hashable, Sendable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case null
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([AnyCodableValue].self) {
            self = .array(v)
        } else {
            self = .null
        }
    }
}
