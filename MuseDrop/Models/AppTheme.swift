//
//  AppTheme.swift
//  Kekasatori
//
//  Accent themes inspired by Renaissance frescoes. "System" follows the Mac's
//  accent color; the others apply a fixed accent across the app.
//

import SwiftUI
import AppKit

/// Light / Dark / System appearance, independent of the accent theme. Applied
/// app-wide via `NSApp.appearance` so it also covers AppKit reader/player windows.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case creation
    case athens
    case venus
    case garden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:   return "System"
        case .creation: return "Creation"
        case .athens:   return "Athens"
        case .venus:    return "Venus"
        case .garden:   return "Garden"
        }
    }

    var subtitle: String {
        switch self {
        case .system:   return "Follows your Mac's accent"
        case .creation: return "Violet & gold — the spark"
        case .athens:   return "Deep indigo"
        case .venus:    return "Rose gold"
        case .garden:   return "Emerald jewel"
        }
    }

    /// Fresco hero shown on the Home screen for this theme.
    var heroImageName: String {
        switch self {
        case .system, .creation: return "Spark"
        case .athens:            return "Forum"
        case .venus:             return "Emergence"
        case .garden:            return "Garden"
        }
    }

    /// The accent color this theme applies. `.system` uses the Mac accent.
    var accent: Color {
        switch self {
        case .system:   return Color.accentColor
        case .creation: return Color(red: 0.49, green: 0.36, blue: 0.98)
        case .athens:   return Color(red: 0.22, green: 0.36, blue: 0.65)
        case .venus:    return Color(red: 0.82, green: 0.46, blue: 0.45)
        case .garden:   return Color(red: 0.16, green: 0.52, blue: 0.40)
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private static let key = "appTheme"
    private static let appearanceKey = "appAppearance"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
            Theme.applyAccent(theme.accent)
        }
    }

    /// System / Light / Dark, overriding the OS appearance for the whole app.
    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            applyAppearance()
        }
    }

    var accent: Color { theme.accent }

    private func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    /// Subtle hue laid over the system background so each theme tints the whole
    /// app. `.system` adds nothing (pure system colors).
    var backgroundWash: Color {
        theme == .system ? .clear : theme.accent.opacity(0.08)
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? ""
        let initial = AppTheme(rawValue: raw) ?? .system
        theme = initial

        let appearanceRaw = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? ""
        let initialAppearance = AppAppearance(rawValue: appearanceRaw) ?? .system
        appearance = initialAppearance

        // didSet doesn't fire for initializer assignments, so apply manually.
        Theme.applyAccent(initial.accent)
        applyAppearance()
    }
}
