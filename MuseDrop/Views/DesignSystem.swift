//
//  DesignSystem.swift
//  MuseDrop
//
//  App-wide visual language. Apple HIG–aligned, content-first, minimal.
//
//  Principles:
//  • Color carries meaning, never decoration. No gradients.
//  • One app accent = the user's system accent (Color.accentColor / .tint).
//  • Status colors are reserved: red = failed/destructive, green = success,
//    orange = in-progress/warning, accent = active/selected, secondary = idle.
//  • Surfaces use system materials and control backgrounds so everything
//    adapts to light/dark and the user's appearance settings.
//

import SwiftUI

// MARK: - Tokens

enum Theme {
    /// 8-pt spacing scale.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Outer page margin for a screen's content column.
        static let page: CGFloat = 28
        /// Vertical gap between major sections of a screen.
        static let section: CGFloat = 28
    }

    /// Continuous corner radii.
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 12
        static let card: CGFloat = 14
        static let pill: CGFloat = 999
    }

    /// Maximum readable content width for a centered screen column.
    static let contentMaxWidth: CGFloat = 920

    // Semantic colors — meaning, not decoration.
    // Active accent is overridable by the selected app theme (see ThemeManager);
    // defaults to the system accent.
    nonisolated(unsafe) private static var _accent: Color = .accentColor
    static var accent: Color { _accent }            // active · selected · primary action
    static func applyAccent(_ color: Color) { _accent = color }
    static let success = Color.green                // completed · available
    static let warning = Color.orange               // merging/converting · warnings
    static let danger = Color.red                    // failed · destructive · delete
    static let idle = Color.secondary                // queued · neutral metadata

    /// Editorial gold — a structural accent for section rules/dividers (not a
    /// status). Used to give list/section screens a crisp, ruled look.
    static let gold = Color(red: 0.78, green: 0.60, blue: 0.20)

    // Surfaces
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let fieldFill = Color(nsColor: .textBackgroundColor)

    enum Motion {
        static let hover = Animation.easeInOut(duration: 0.18)
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }
}

// MARK: - Download status styling

extension Theme {
    static func color(for status: DownloadStatus) -> Color {
        switch status {
        case .queued:                  return .secondary
        case .downloading:             return .accentColor
        case .merging, .converting:    return .orange
        case .completed:               return .green
        case .failed:                  return .red
        }
    }

    static func icon(for status: DownloadStatus) -> String {
        switch status {
        case .queued:       return "clock"
        case .downloading:  return "arrow.down.circle"
        case .merging:      return "arrow.triangle.merge"
        case .converting:   return "arrow.2.squarepath"
        case .completed:    return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }

    static func label(for status: DownloadStatus) -> String {
        switch status {
        case .queued:       return "Queued"
        case .downloading:  return "Downloading"
        case .merging:      return "Merging"
        case .converting:   return "Converting"
        case .completed:    return "Completed"
        case .failed:       return "Failed"
        }
    }
}

// MARK: - Surface modifiers

extension View {
    /// Standard content card: control-background fill, hairline border, soft shadow.
    /// Adapts to light/dark; no gradients.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    /// Floating chrome (search/filter bars, selection toolbars). Uses Liquid Glass
    /// on macOS 26, falling back to a system material on earlier versions.
    @ViewBuilder
    func floatingChrome(radius: CGFloat = Theme.Radius.lg) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
                )
        }
    }

    /// Centers a screen's content in a readable column with consistent page margins.
    func screenColumn(maxWidth: CGFloat = Theme.contentMaxWidth) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.page)
    }
}

// MARK: - Reusable components

/// A restrained screen header: SF Symbol in the accent, title, optional subtitle.
/// Sizes follow macOS conventions (no oversized iOS-style display type).
struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String
    /// Optional brand image (asset name) shown instead of the SF Symbol.
    var brandImage: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            if let brandImage {
                Image(brandImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A thin editorial gold rule — the structural separator used to give screens a
/// crisp, ruled look. Horizontal by default; pass `axis: .vertical` for a column
/// divider. Reusable across Discover, Library, Home, the reader, etc.
struct SectionRule: View {
    var axis: Axis = .horizontal
    var color: Color = Theme.gold
    var thickness: CGFloat = 1.5
    var opacity: Double = 0.85

    var body: some View {
        Rectangle()
            .fill(color)
            .opacity(opacity)
            .frame(width: axis == .vertical ? thickness : nil,
                   height: axis == .horizontal ? thickness : nil)
            .frame(maxWidth: axis == .horizontal ? .infinity : nil,
                   maxHeight: axis == .vertical ? .infinity : nil)
    }
}

/// A title with a leading gold-tinted symbol over a gold rule — the ruled
/// section header used to head a screen's sections consistently.
struct RuledSectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(Theme.gold)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: Theme.Spacing.md)
                if let trailing { trailing }
            }
            SectionRule()
        }
    }
}

/// Lightweight section heading used between cards/lists.
struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .secondary
    var trailing: AnyView? = nil

    init(_ title: String, systemImage: String? = nil, tint: Color = .secondary, trailing: AnyView? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

/// Compact status pill: tinted text + icon on a soft tinted capsule.
struct StatusPill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Standard empty state: large hierarchical glyph, title, message.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

/// A search field styled consistently across screens.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 1)
        .floatingChrome(radius: Theme.Radius.md)
    }
}
