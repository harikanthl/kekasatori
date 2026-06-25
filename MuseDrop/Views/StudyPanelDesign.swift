//
//  StudyPanelDesign.swift
//  MuseDrop
//
//  Shared visual language for the player study sidebar.
//

import SwiftUI

enum StudyPanelDesign {
    /// Unified with the app-wide accent (see DesignSystem.Theme.accent).
    static let accent = Theme.accent
    
    static let headerPadding = EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16)
    static let contentPadding: CGFloat = 16
    static let tabBarHeight: CGFloat = 36
    static let cornerRadius: CGFloat = 10
    
    static func chipBackground(_ color: Color = Color.primary.opacity(0.06)) -> some ShapeStyle {
        color
    }
}

struct StudyStatusChip: View {
    let title: String
    let icon: String
    var tint: Color = .secondary
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(StudyPanelDesign.chipBackground(tint.opacity(0.12)))
        }
    }
}

struct StudyTabBar: View {
    let tabs: [AIStudyTab]
    @Binding var selection: AIStudyTab
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    Button {
                        selection = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .medium))
                            Text(tab.shortLabel)
                                .font(.caption.weight(selection == tab ? .semibold : .regular))
                        }
                        .foregroundStyle(selection == tab ? StudyPanelDesign.accent : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(StudyPanelDesign.accent.opacity(0.12))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tab.rawValue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

private extension AIStudyTab {
    var shortLabel: String {
        switch self {
        case .tutor: return "Tutor"
        case .canvas: return "Canvas"
        case .notebook: return "Notebook"
        case .transcript: return "Script"
        case .summary: return "Summary"
        case .notes: return "Notes"
        case .flashcards: return "Cards"
        case .mindMap: return "Map"
        case .concepts: return "Terms"
        }
    }
}

// MARK: - Flashcards

struct StudyFlashcardSession: View {
    let front: String
    let back: String
    let tag: String
    let index: Int
    let total: Int
    let isShowingBack: Bool
    let onFlip: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            sessionHeader
            
            StudyFlashcardDeck(
                front: front,
                back: back,
                tag: tag,
                index: index,
                total: total,
                isShowingBack: isShowingBack,
                onTap: onFlip
            )
            
            StudyFlashcardControls(
                canNavigate: total > 1,
                isShowingBack: isShowingBack,
                onPrevious: onPrevious,
                onFlip: onFlip,
                onNext: onNext
            )
        }
    }
    
    private var sessionHeader: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(index + 1), total: Double(total))
                .progressViewStyle(.linear)
                .tint(StudyPanelDesign.accent)
            
            Text("Card \(index + 1) of \(total)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

struct StudyFlashcardDeck: View {
    let front: String
    let back: String
    let tag: String
    let index: Int
    let total: Int
    let isShowingBack: Bool
    let onTap: () -> Void
    
    var body: some View {
        ZStack(alignment: .top) {
            ForEach(stackLayers, id: \.self) { layer in
                cardPlate
                    .offset(y: CGFloat(layer) * 6)
                    .scaleEffect(1 - CGFloat(layer) * 0.02, anchor: .top)
                    .opacity(0.45 - Double(layer) * 0.1)
            }
            
            flippableCard
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.bottom, CGFloat(stackLayers.count) * 6 + 6)
    }
    
    private var stackLayers: [Int] {
        let remaining = max(0, total - index - 1)
        return (0..<min(2, remaining)).map { $0 + 1 }.reversed()
    }
    
    private var flippableCard: some View {
        ZStack {
            cardFace(text: front, isBack: false)
                .opacity(isShowingBack ? 0 : 1)
            
            cardFace(text: back, isBack: true)
                .opacity(isShowingBack ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(
            .degrees(isShowingBack ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isShowingBack)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isShowingBack ? "Answer: \(back)" : "Question: \(front)")
        .accessibilityHint("Double tap to flip card")
        .accessibilityAction(named: "Flip") { onTap() }
    }
    
    private var cardPlate: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(nsColor: .separatorColor).opacity(0.18))
            .frame(minHeight: 196)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04))
            }
    }
    
    private func cardFace(text: String, isBack: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(cardFill(isBack: isBack))
            .overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    
                    Text(text)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.7)
                        .lineLimit(8)
                    
                    Spacer(minLength: 16)
                    
                    footer(isBack: isBack)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
            .frame(minHeight: 196)
    }
    
    private func cardFill(isBack: Bool) -> some ShapeStyle {
        if isBack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    StudyPanelDesign.accent.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    @ViewBuilder
    private func footer(isBack: Bool) -> some View {
        VStack(spacing: 8) {
            if !isBack {
                Label("Tap to flip", systemImage: "hand.tap")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            
            if !tag.isEmpty, tag.lowercased() != "general" {
                Text(tag.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    }
            }
        }
        .padding(.bottom, 18)
    }
}

struct StudyFlashcardControls: View {
    let canNavigate: Bool
    let isShowingBack: Bool
    let onPrevious: () -> Void
    let onFlip: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            controlButton(
                icon: "chevron.left",
                label: "Previous card",
                action: onPrevious
            )
            .disabled(!canNavigate)
            
            Spacer(minLength: 0)
            
            controlButton(
                icon: "arrow.triangle.2.circlepath",
                label: isShowingBack ? "Show question" : "Show answer",
                action: onFlip
            )
            
            Spacer(minLength: 0)
            
            controlButton(
                icon: "chevron.right",
                label: "Next card",
                action: onNext
            )
            .disabled(!canNavigate)
        }
        .padding(.horizontal, 8)
    }
    
    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}
