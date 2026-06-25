//
//  ConceptGraphCanvasView.swift
//  MuseDrop
//

import SwiftUI
import AppKit

struct ConceptGraphCanvasView: View {
    let mindMap: MindMap
    let concepts: [KeyConcept]
    var minHeight: CGFloat = 440
    
    @State private var scale: CGFloat = 1
    @State private var magnifyBaseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOrigin: CGSize = .zero
    @State private var selectedNodeId: String?
    @State private var canvasViewSize: CGSize = .zero
    @State private var layout: ConceptGraphLayout.LayoutResult

    init(mindMap: MindMap, concepts: [KeyConcept], minHeight: CGFloat = 440) {
        self.mindMap = mindMap
        self.concepts = concepts
        self.minHeight = minHeight
        _layout = State(initialValue: ConceptGraphLayout.layout(mindMap: mindMap, concepts: concepts))
    }

    private func rebuildLayout() {
        layout = ConceptGraphLayout.layout(mindMap: mindMap, concepts: concepts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlBar
            
            if layout.displayNodes.isEmpty {
                emptyCanvas
            } else {
                GeometryReader { proxy in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
                        
                        graphSurface(viewSize: proxy.size)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .onAppear {
                        let size = proxy.size
                        Task { @MainActor in
                            canvasViewSize = size
                            fitToView(viewSize: size)
                        }
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        canvasViewSize = newSize
                    }
                    .onChange(of: mindMap.centralTopic) { _, _ in
                        rebuildLayout()
                        Task { @MainActor in
                            fitToView(viewSize: canvasViewSize)
                        }
                    }
                    .onChange(of: concepts.count) { _, _ in
                        rebuildLayout()
                        Task { @MainActor in
                            fitToView(viewSize: canvasViewSize)
                        }
                    }
                }
                .frame(minHeight: minHeight)
                .background(ScrollWheelZoomHost(scale: $scale))
            }
            
            if let selected = selectedConcept {
                conceptDetailCard(selected)
            }
        }
    }
    
    private var controlBar: some View {
        HStack(spacing: 8) {
            Label("Drag to pan · Scroll to zoom", systemImage: "hand.draw")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            Spacer()
            
            Button { adjustZoom(by: 0.85) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom out")
            
            Text("\(Int(scale * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44)
            
            Button { adjustZoom(by: 1.18) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom in")
            
            Button {
                selectedNodeId = nil
                fitToView(viewSize: canvasViewSize)
            } label: {
                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    private var emptyCanvas: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No concept graph yet")
                .font(.subheadline.weight(.semibold))
            Text("Generate a study pack to build an interactive concept map.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        }
    }
    
    private func graphSurface(viewSize: CGSize) -> some View {
        let layout = layout
        
        return ZStack {
            Canvas { context, size in
                drawGrid(in: &context, size: size)
                for edge in layout.displayEdges {
                    guard
                        let from = layout.positions[edge.fromId],
                        let to = layout.positions[edge.toId]
                    else { continue }
                    
                    let start = transformed(point: from, viewSize: viewSize, layout: layout)
                    let end = transformed(point: to, viewSize: viewSize, layout: layout)
                    var path = Path()
                    path.move(to: start)
                    
                    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    let dx = end.x - start.x
                    let dy = end.y - start.y
                    let control = CGPoint(x: mid.x - dy * 0.12, y: mid.y + dx * 0.12)
                    path.addQuadCurve(to: end, control: control)
                    
                    context.stroke(
                        path,
                        with: .color(Color.accentColor.opacity(selectedNodeId == edge.toId || selectedNodeId == edge.fromId ? 0.75 : 0.35)),
                        style: StrokeStyle(lineWidth: selectedNodeId == edge.toId || selectedNodeId == edge.fromId ? 2.5 : 1.5, lineCap: .round)
                    )
                }
            }
            .allowsHitTesting(false)
            
            ForEach(layout.displayNodes) { node in
                if let point = layout.positions[node.id] {
                    let screenPoint = transformed(point: point, viewSize: viewSize, layout: layout)
                    nodeButton(node: node, at: screenPoint)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(panGesture)
        .simultaneousGesture(magnifyGesture)
        .onTapGesture {
            selectedNodeId = nil
        }
    }
    
    private func nodeButton(node: MindMapNode, at point: CGPoint) -> some View {
        let concept = concept(matching: node)
        let isSelected = selectedNodeId == node.id
        
        return Button {
            selectedNodeId = node.id
        } label: {
            nodeLabel(node: node, concept: concept, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .position(point)
    }
    
    private func nodeLabel(node: MindMapNode, concept: KeyConcept?, isSelected: Bool) -> some View {
        let importance = concept?.importance ?? "medium"
        
        return VStack(spacing: 4) {
            Text(node.label)
                .font(font(for: node.level))
                .fontWeight(node.level == 0 ? .bold : .semibold)
                .multilineTextAlignment(.center)
                .lineLimit(node.level == 0 ? 3 : 2)
                .foregroundStyle(node.level == 0 ? .white : .primary)
            
            if node.level == 1, concept != nil {
                Text(importance.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(importanceColor(importance))
            }
        }
        .padding(.horizontal, horizontalPadding(for: node.level))
        .padding(.vertical, verticalPadding(for: node.level))
        .frame(maxWidth: maxWidth(for: node.level))
        .background {
            if node.level == 0 {
                RoundedRectangle(cornerRadius: cornerRadius(for: node.level), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.pink, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 10 : 4, y: 3)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius(for: node.level), style: .continuous)
                    .fill(nodeFill(level: node.level, importance: importance, isSelected: isSelected))
                    .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 10 : 4, y: 3)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius(for: node.level), style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
    
    private func conceptDetailCard(_ concept: KeyConcept) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(concept.term)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                importanceBadge(concept.importance)
            }
            Text(concept.definition)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        }
    }
    
    private var selectedConcept: KeyConcept? {
        guard let selectedNodeId else { return nil }
        if let node = layout.displayNodes.first(where: { $0.id == selectedNodeId }) {
            return concept(matching: node)
        }
        return concepts.first(where: { $0.id == selectedNodeId })
    }
    
    private func concept(matching node: MindMapNode) -> KeyConcept? {
        let normalized = node.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = concepts.first(where: { $0.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }) {
            return exact
        }
        return concepts.first {
            normalized.contains($0.term.lowercased()) || $0.term.lowercased().contains(normalized)
        }
    }
    
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                offset = CGSize(
                    width: dragOrigin.width + value.translation.width,
                    height: dragOrigin.height + value.translation.height
                )
            }
            .onEnded { _ in
                dragOrigin = offset
            }
    }
    
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(magnifyBaseScale * value.magnification, 0.25), 3.5)
            }
            .onEnded { _ in
                magnifyBaseScale = scale
            }
    }
    
    private func transformed(
        point: CGPoint,
        viewSize: CGSize,
        layout: ConceptGraphLayout.LayoutResult
    ) -> CGPoint {
        let base = CGPoint(
            x: (viewSize.width - layout.bounds.width * scale) / 2 + point.x * scale + offset.width,
            y: (viewSize.height - layout.bounds.height * scale) / 2 + point.y * scale + offset.height
        )
        return base
    }
    
    private func fitToView(viewSize: CGSize) {
        let layout = layout
        guard layout.bounds.width > 0, layout.bounds.height > 0 else { return }
        
        let fitScale = min(
            viewSize.width / layout.bounds.width,
            viewSize.height / layout.bounds.height
        ) * 0.92
        
        // Allow shrinking enough for large graphs to fully fit. Because layout
        // spacing exceeds node width, fitting can never overlap siblings; the
        // user can scroll-zoom in. A 0.35 floor previously forced a squished,
        // clipped pile for big maps.
        scale = min(max(fitScale, 0.12), 1.25)
        magnifyBaseScale = scale
        offset = .zero
        dragOrigin = .zero
    }
    
    private func adjustZoom(by factor: CGFloat) {
        scale = min(max(scale * factor, 0.25), 3.5)
        magnifyBaseScale = scale
    }
    
    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 28
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(.primary.opacity(0.04)), lineWidth: 1)
    }
    
    private func font(for level: Int) -> Font {
        switch level {
        case 0: return .headline
        case 1: return .subheadline
        default: return .caption
        }
    }
    
    private func horizontalPadding(for level: Int) -> CGFloat {
        level == 0 ? 20 : (level == 1 ? 14 : 10)
    }
    
    private func verticalPadding(for level: Int) -> CGFloat {
        level == 0 ? 14 : (level == 1 ? 10 : 8)
    }
    
    private func maxWidth(for level: Int) -> CGFloat {
        level == 0 ? 220 : (level == 1 ? 168 : 140)
    }
    
    private func cornerRadius(for level: Int) -> CGFloat {
        level == 0 ? 18 : 12
    }
    
    private func nodeFill(level: Int, importance: String, isSelected: Bool) -> Color {
        if level == 0 {
            return .clear
        }
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        return importanceColor(importance).opacity(level == 1 ? 0.14 : 0.1)
    }
    
    private func importanceBadge(_ importance: String) -> some View {
        Text(importance.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(importanceColor(importance).opacity(0.15)))
            .foregroundStyle(importanceColor(importance))
    }
    
    private func importanceColor(_ importance: String) -> Color {
        switch importance.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .blue
        }
    }
}

// MARK: - Scroll wheel zoom (macOS)

private struct ScrollWheelZoomHost: NSViewRepresentable {
    @Binding var scale: CGFloat
    
    func makeNSView(context: Context) -> ScrollWheelZoomNSView {
        let view = ScrollWheelZoomNSView()
        view.scale = scale
        let binding = $scale
        view.onZoom = { factor in
            binding.wrappedValue = min(max(binding.wrappedValue * factor, 0.25), 3.5)
        }
        return view
    }

    func updateNSView(_ nsView: ScrollWheelZoomNSView, context: Context) {
        nsView.scale = scale
        let binding = $scale
        nsView.onZoom = { factor in
            binding.wrappedValue = min(max(binding.wrappedValue * factor, 0.25), 3.5)
        }
    }
}

private final class ScrollWheelZoomNSView: NSView {
    var onZoom: ((CGFloat) -> Void)?
    var scale: CGFloat = 1
    
    override var acceptsFirstResponder: Bool { true }
    
    override func scrollWheel(with event: NSEvent) {
        guard event.deltaY != 0 else {
            super.scrollWheel(with: event)
            return
        }
        let factor: CGFloat = event.deltaY > 0 ? 1.08 : 0.92
        onZoom?(factor)
    }
}
