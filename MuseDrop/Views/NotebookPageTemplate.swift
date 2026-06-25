//
//  NotebookPageTemplate.swift
//  MuseDrop
//

import SwiftUI

enum NotebookPageTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case ruled
    case dot
    case grid
    case cornell
    case columns
    case checklist
    case blank
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .ruled: return "Ruled"
        case .dot: return "Dot Grid"
        case .grid: return "Graph"
        case .cornell: return "Cornell"
        case .columns: return "Two Column"
        case .checklist: return "Checklist"
        case .blank: return "Blank"
        }
    }
    
    var subtitle: String {
        switch self {
        case .ruled: return "Classic notebook lines"
        case .dot: return "Bullet journal dots"
        case .grid: return "Square graph paper"
        case .cornell: return "Cue · Notes · Summary"
        case .columns: return "Split page notes"
        case .checklist: return "Tasks and ideas"
        case .blank: return "Clean canvas"
        }
    }
    
    var icon: String {
        switch self {
        case .ruled: return "line.3.horizontal"
        case .dot: return "circle.grid.3x3.fill"
        case .grid: return "grid"
        case .cornell: return "tablecells"
        case .columns: return "rectangle.split.2x1"
        case .checklist: return "checklist"
        case .blank: return "doc"
        }
    }
    
    struct Layout: Sendable {
        let lineSpacing: CGFloat
        let marginInset: CGFloat
        let topInset: CGFloat
        let bottomInset: CGFloat
        let usesFixedLineHeight: Bool
    }
    
    var layout: Layout {
        switch self {
        case .ruled:
            return Layout(lineSpacing: 28, marginInset: 56, topInset: 20, bottomInset: 20, usesFixedLineHeight: true)
        case .dot:
            return Layout(lineSpacing: 24, marginInset: 28, topInset: 20, bottomInset: 20, usesFixedLineHeight: false)
        case .grid:
            return Layout(lineSpacing: 20, marginInset: 24, topInset: 20, bottomInset: 20, usesFixedLineHeight: false)
        case .cornell:
            return Layout(lineSpacing: 28, marginInset: 56, topInset: 20, bottomInset: 96, usesFixedLineHeight: true)
        case .columns:
            return Layout(lineSpacing: 28, marginInset: 24, topInset: 20, bottomInset: 20, usesFixedLineHeight: true)
        case .checklist:
            return Layout(lineSpacing: 28, marginInset: 40, topInset: 20, bottomInset: 20, usesFixedLineHeight: true)
        case .blank:
            return Layout(lineSpacing: 28, marginInset: 24, topInset: 20, bottomInset: 20, usesFixedLineHeight: false)
        }
    }
    
    var paperColors: [Color] {
        switch self {
        case .ruled, .cornell, .columns:
            return [
                Color(red: 0.99, green: 0.98, blue: 0.94),
                Color(red: 0.97, green: 0.96, blue: 0.91)
            ]
        case .dot, .checklist:
            return [
                Color(red: 0.985, green: 0.98, blue: 0.97),
                Color(red: 0.96, green: 0.975, blue: 0.985)
            ]
        case .grid:
            return [
                Color(red: 0.97, green: 0.99, blue: 0.97),
                Color(red: 0.94, green: 0.97, blue: 0.95)
            ]
        case .blank:
            return [
                Color(red: 0.995, green: 0.995, blue: 0.995),
                Color(red: 0.975, green: 0.975, blue: 0.975)
            ]
        }
    }
    
    static func from(raw: String) -> NotebookPageTemplate {
        NotebookPageTemplate(rawValue: raw) ?? .ruled
    }
}

struct NotebookTemplateBackground: View {
    let template: NotebookPageTemplate
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: template.paperColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                templateOverlay(in: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
    }
    
    @ViewBuilder
    private func templateOverlay(in size: CGSize) -> some View {
        switch template {
        case .ruled:
            ruledOverlay(in: size)
        case .dot:
            dotOverlay(spacing: 20)
        case .grid:
            gridOverlay(spacing: 20)
        case .cornell:
            cornellOverlay(in: size)
        case .columns:
            columnsOverlay(in: size)
        case .checklist:
            checklistOverlay(in: size)
        case .blank:
            EmptyView()
        }
    }
    
    private func ruledOverlay(in size: CGSize) -> some View {
        let layout = template.layout
        return ZStack {
            verticalMarginLine(x: layout.marginInset, height: size.height)
            horizontalRules(
                in: size,
                spacing: layout.lineSpacing,
                topPadding: layout.lineSpacing + 18,
                left: 16,
                right: 16
            )
        }
    }
    
    private func dotOverlay(spacing: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let cols = Int(canvasSize.width / spacing)
            let rows = Int(canvasSize.height / spacing)
            for row in 0...rows {
                for col in 0...cols {
                    let point = CGPoint(x: CGFloat(col) * spacing + 12, y: CGFloat(row) * spacing + 12)
                    let rect = CGRect(x: point.x - 1.2, y: point.y - 1.2, width: 2.4, height: 2.4)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.blue.opacity(0.22)))
                }
            }
        }
    }
    
    private func gridOverlay(spacing: CGFloat) -> some View {
        Canvas { context, canvasSize in
            var path = Path()
            var x: CGFloat = 12
            while x < canvasSize.width - 12 {
                path.move(to: CGPoint(x: x, y: 12))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height - 12))
                x += spacing
            }
            var y: CGFloat = 12
            while y < canvasSize.height - 12 {
                path.move(to: CGPoint(x: 12, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width - 12, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(Color.green.opacity(0.16)), lineWidth: 0.8)
        }
    }
    
    private func cornellOverlay(in size: CGSize) -> some View {
        let cueX = size.width * 0.28
        let summaryY = size.height - 88
        
        return ZStack {
            verticalMarginLine(x: 56, height: size.height)
            
            Path { path in
                path.move(to: CGPoint(x: cueX, y: 12))
                path.addLine(to: CGPoint(x: cueX, y: summaryY))
            }
            .stroke(Color.orange.opacity(0.35), lineWidth: 1.2)
            
            Path { path in
                path.move(to: CGPoint(x: 16, y: summaryY))
                path.addLine(to: CGPoint(x: size.width - 16, y: summaryY))
            }
            .stroke(Color.orange.opacity(0.35), lineWidth: 1.2)
            
            horizontalRules(
                in: size,
                spacing: 28,
                topPadding: 46,
                left: cueX + 8,
                right: 16,
                maxY: summaryY - 4
            )
            
            horizontalRules(
                in: size,
                spacing: 28,
                topPadding: 46,
                left: 64,
                right: size.width - cueX + 6,
                maxY: summaryY - 4,
                color: Color.blue.opacity(0.1)
            )
            
            templateLabel("Cue", at: CGPoint(x: 64, y: 18))
            templateLabel("Notes", at: CGPoint(x: cueX + 10, y: 18))
            templateLabel("Summary", at: CGPoint(x: 64, y: summaryY + 8))
        }
    }
    
    private func columnsOverlay(in size: CGSize) -> some View {
        let midX = size.width * 0.5
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: midX, y: 12))
                path.addLine(to: CGPoint(x: midX, y: size.height - 12))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            .foregroundStyle(Color.purple.opacity(0.28))
            
            horizontalRules(in: size, spacing: 28, topPadding: 46, left: 16, right: 16)
            
            templateLabel("Left", at: CGPoint(x: 20, y: 18))
            templateLabel("Right", at: CGPoint(x: midX + 8, y: 18))
        }
    }
    
    private func checklistOverlay(in size: CGSize) -> some View {
        let layout = template.layout
        return ZStack {
            horizontalRules(
                in: size,
                spacing: layout.lineSpacing,
                topPadding: layout.lineSpacing + 18,
                left: layout.marginInset,
                right: 16
            )
            
            Canvas { context, canvasSize in
                var y = layout.lineSpacing + 18
                while y < canvasSize.height - 16 {
                    let rect = CGRect(x: 18, y: y - 10, width: 14, height: 14)
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(Color.secondary.opacity(0.35)),
                        lineWidth: 1
                    )
                    y += layout.lineSpacing
                }
            }
        }
    }
    
    private func verticalMarginLine(x: CGFloat, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(StudyPanelDesign.accent.opacity(0.35), lineWidth: 1.5)
    }
    
    private func horizontalRules(
        in size: CGSize,
        spacing: CGFloat,
        topPadding: CGFloat,
        left: CGFloat,
        right: CGFloat,
        maxY: CGFloat? = nil,
        color: Color = Color.blue.opacity(0.14)
    ) -> some View {
        Path { path in
            var y = topPadding
            let limit = maxY ?? (size.height - 16)
            while y < limit {
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: size.width - right, y: y))
                y += spacing
            }
        }
        .stroke(color, lineWidth: 0.8)
    }
    
    private func templateLabel(_ text: String, at point: CGPoint) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
            .position(x: point.x + 24, y: point.y + 6)
    }
}

struct NotebookTemplatePicker: View {
    let selection: NotebookPageTemplate
    let onSelect: (NotebookPageTemplate) -> Void
    
    var body: some View {
        Menu {
            ForEach(NotebookPageTemplate.allCases) { template in
                Button {
                    onSelect(template)
                } label: {
                    Label {
                        Text("\(template.title) — \(template.subtitle)")
                    } icon: {
                        Image(systemName: template.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selection.icon)
                    .font(.caption.weight(.semibold))
                Text(selection.title)
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Page template")
    }
}
