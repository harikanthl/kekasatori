//
//  NotebookPageFormatting.swift
//  MuseDrop
//

import AppKit
import SwiftUI

/// Ink and typography defaults for light notebook paper (not system label color).
enum NotebookInk {
    static let defaultHex = "1A1714"
    static let blueHex = "1B3A6B"
    static let redHex = "8B1E1E"
    static let greenHex = "1E4D2B"
    static let purpleHex = "4A2D6E"
    static let brownHex = "5C4033"
    
    static let palette: [(name: String, hex: String)] = [
        ("Black", defaultHex),
        ("Blue", blueHex),
        ("Red", redHex),
        ("Green", greenHex),
        ("Purple", purpleHex),
        ("Brown", brownHex)
    ]
    
    static let highlightPalette: [(name: String, hex: String)] = [
        ("Yellow", "FFF59D"),
        ("Green", "C8E6C9"),
        ("Blue", "BBDEFB"),
        ("Pink", "F8BBD0"),
        ("Orange", "FFE0B2")
    ]
    
    static var defaultNSColor: NSColor { nsColor(hex: defaultHex) }
    
    static func nsColor(hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: CGFloat
        switch cleaned.count {
        case 6:
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
        default:
            r = 0.1; g = 0.09; b = 0.08
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    
    static func swiftUIColor(hex: String) -> Color {
        Color(nsColor: nsColor(hex: hex))
    }
}

struct NotebookPageFormatting: Codable, Equatable, Hashable, Sendable {
    var fontSize: Double
    var fontFamily: NotebookFontFamily
    var inkColorHex: String
    
    static let `default` = NotebookPageFormatting(
        fontSize: 15,
        fontFamily: .system,
        inkColorHex: NotebookInk.defaultHex
    )
    
    var font: NSFont {
        fontFamily.nsFont(size: fontSize)
    }
    
    var inkColor: NSColor {
        NotebookInk.nsColor(hex: inkColorHex)
    }
    
    func encodedJSON() -> String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
    }
    
    static func decode(from json: String) -> NotebookPageFormatting {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(NotebookPageFormatting.self, from: data) else {
            return .default
        }
        return value
    }
}

enum NotebookFontFamily: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case system
    case serif
    case mono
    case rounded
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .system: return "System"
        case .serif: return "Serif"
        case .mono: return "Mono"
        case .rounded: return "Rounded"
        }
    }
    
    func nsFont(size: Double) -> NSFont {
        let pointSize = CGFloat(size)
        switch self {
        case .system:
            return NSFont.systemFont(ofSize: pointSize)
        case .serif:
            return NSFont(name: "Georgia", size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        case .rounded:
            if let descriptor = NSFont.systemFont(ofSize: pointSize).fontDescriptor.withDesign(.rounded) {
                return NSFont(descriptor: descriptor, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
            }
            return NSFont.systemFont(ofSize: pointSize)
        }
    }
}

enum NotebookFormatCommand: Equatable {
    case bold
    case italic
    case underline
    case strikethrough
    case highlight(String?)
    case alignment(NSTextAlignment)
    case clearFormatting
    case increaseSize
    case decreaseSize
}
