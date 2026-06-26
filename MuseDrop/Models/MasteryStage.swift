//
//  MasteryStage.swift
//  Kekasatori
//
//  A study pack's mastery level, framed as the Shu-Ha-Ri stages of learning:
//  Shu (follow — learn the fundamentals), Ha (break — practice and take apart),
//  Ri (transcend — mastered and internalized).
//

import SwiftUI

enum MasteryStage: String, CaseIterable, Identifiable, Sendable {
    case learning    // Shu
    case practicing  // Ha
    case mastered    // Ri

    var id: String { rawValue }

    /// Plain-language label shown to the user.
    var label: String {
        switch self {
        case .learning:   return "Learning"
        case .practicing: return "Practicing"
        case .mastered:   return "Mastered"
        }
    }

    /// The Shu-Ha-Ri stage name, shown as a subtle subtitle.
    var stageName: String {
        switch self {
        case .learning:   return "Shu"
        case .practicing: return "Ha"
        case .mastered:   return "Ri"
        }
    }

    /// Filled-fraction glyph: empty → half → full as mastery grows.
    var glyph: String {
        switch self {
        case .learning:   return "circle"
        case .practicing: return "circle.lefthalf.filled"
        case .mastered:   return "circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .learning:   return Color(red: 0.52, green: 0.58, blue: 0.70)  // slate
        case .practicing: return Color(red: 0.85, green: 0.60, blue: 0.22)  // amber
        case .mastered:   return Color(red: 0.25, green: 0.70, blue: 0.45)  // green
        }
    }

    /// Low → high ordering for sorting (unset is treated as 0 by callers).
    var rank: Int {
        switch self {
        case .learning:   return 1
        case .practicing: return 2
        case .mastered:   return 3
        }
    }
}
