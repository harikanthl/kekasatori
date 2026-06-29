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
    /// The expand-to-fullscreen control is hidden inside the expanded sheet
    /// itself so the map can't recursively present a copy of itself.
    var allowsExpand: Bool = true

    @State private var scale: CGFloat = 1
    @State private var magnifyBaseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOrigin: CGSize = .zero
    @State private var selectedNodeId: String?
    @State private var canvasViewSize: CGSize = .zero
    @State private var isExpanded = false
    @State private var layout: ConceptGraphLayout.LayoutResult

    init(mindMap: MindMap, concepts: [KeyConcept], minHeight: CGFloat = 440, allowsExpand: Bool = true) {
        self.mindMap = mindMap
        self.concepts = concepts
        self.minHeight = minHeight
        self.allowsExpand = allowsExpand
        _layout = State(initialValue: ConceptGraphLayout.layout(mindMap: mindMap, concepts: concepts))
    }

    private func rebuildLayout() {
        layout = ConceptGraphLayout.layout(mindMap: mindMap, concepts: concepts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlBar

            if !branchLegendNodes.isEmpty {
                legend
            }

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
                .background(ScrollWheelZoomHost { factor in
                    adjustZoom(by: factor)
                })
            }
            
            if let selected = selectedConcept {
                conceptDetailCard(selected)
            }
        }
        .sheet(isPresented: $isExpanded) {
            expandedSheet
        }
    }

    private var expandedSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mindMap.centralTopic.isEmpty ? "Mind Map" : mindMap.centralTopic)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Done") { isExpanded = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ConceptGraphCanvasView(
                mindMap: mindMap,
                concepts: concepts,
                minHeight: 560,
                allowsExpand: false
            )
            .padding(16)
        }
        .frame(minWidth: 720, idealWidth: 1100, minHeight: 560, idealHeight: 820)
    }

    /// Level-1 nodes, one per colour family, in branch order — the legend rows.
    private var branchLegendNodes: [MindMapNode] {
        layout.displayNodes
            .filter { $0.level == 1 }
            .sorted { (layout.branchIndex[$0.id] ?? 0) < (layout.branchIndex[$1.id] ?? 0) }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(branchLegendNodes) { node in
                    let isFocused = selectedNodeId == node.id
                    Button {
                        selectedNodeId = isFocused ? nil : node.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(branchColor(for: node.id))
                                .frame(width: 9, height: 9)
                            Text(node.label)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(isFocused ? Color.primary : .secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(
                                isFocused
                                    ? branchColor(for: node.id).opacity(0.18)
                                    : Color.primary.opacity(0.05)
                            )
                        }
                        .overlay {
                            Capsule().strokeBorder(
                                isFocused ? branchColor(for: node.id).opacity(0.6) : .clear,
                                lineWidth: 1
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
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

            if allowsExpand {
                Button {
                    isExpanded = true
                } label: {
                    Label("Expand", systemImage: "macwindow")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open the map in a large window")
            }
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
        let lineage = focusLineage

        // One transform group, like an SVG <g transform>. Edges, nodes, and
        // their text all live at natural layout coordinates and scale together,
        // so zooming out shrinks the whole map uniformly and labels can never
        // pile up into a squished, overlapping mass.
        return ZStack {
            Canvas { context, _ in
                drawGrid(in: &context, size: viewSize)
            }
            .allowsHitTesting(false)

            graphContent(layout: layout, lineage: lineage)
                .scaleEffect(scale)
                .offset(offset)
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .contentShape(Rectangle())
        .gesture(panGesture)
        .simultaneousGesture(magnifyGesture)
        .onTapGesture {
            selectedNodeId = nil
        }
    }

    /// The map drawn at its natural (unscaled) layout coordinates. The parent
    /// applies a single `scaleEffect` + `offset` so everything transforms as one.
    private func graphContent(layout: ConceptGraphLayout.LayoutResult, lineage: Set<String>?) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in layout.displayEdges {
                    guard
                        let start = layout.positions[edge.fromId],
                        let end = layout.positions[edge.toId]
                    else { continue }

                    var path = Path()
                    path.move(to: start)

                    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    let dx = end.x - start.x
                    let dy = end.y - start.y
                    let control = CGPoint(x: mid.x - dy * 0.12, y: mid.y + dx * 0.12)
                    path.addQuadCurve(to: end, control: control)

                    let inFocus = lineage.map { $0.contains(edge.fromId) && $0.contains(edge.toId) }
                    let emphasized = inFocus == true
                    // Edges take the colour of the branch they feed into.
                    let color = branchColor(for: edge.toId)
                    let opacity: Double = lineage == nil ? 0.55 : (emphasized ? 0.9 : 0.07)
                    context.stroke(
                        path,
                        with: .color(color.opacity(opacity)),
                        style: StrokeStyle(lineWidth: emphasized ? 3 : 1.6, lineCap: .round)
                    )
                }
            }
            .frame(width: layout.bounds.width, height: layout.bounds.height)
            .allowsHitTesting(false)

            ForEach(layout.displayNodes) { node in
                if let point = layout.positions[node.id] {
                    nodeButton(node: node, at: point, lineage: lineage)
                }
            }
        }
        .frame(width: layout.bounds.width, height: layout.bounds.height, alignment: .topLeading)
    }

    private func nodeButton(node: MindMapNode, at point: CGPoint, lineage: Set<String>?) -> some View {
        let concept = concept(matching: node)
        let isSelected = selectedNodeId == node.id
        let dimmed = lineage.map { !$0.contains(node.id) } ?? false

        return Button {
            selectedNodeId = (selectedNodeId == node.id) ? nil : node.id
        } label: {
            nodeLabel(node: node, concept: concept, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.2 : 1)
        .animation(.easeOut(duration: 0.2), value: dimmed)
        .position(point)
    }

    private func nodeLabel(node: MindMapNode, concept: KeyConcept?, isSelected: Bool) -> some View {
        let importance = concept?.importance ?? "medium"
        let color = branchColor(for: node.id)

        return VStack(spacing: 4) {
            Text(node.label)
                .font(font(for: node.level))
                .fontWeight(node.level == 0 ? .bold : .semibold)
                .multilineTextAlignment(.center)
                .lineLimit(node.level == 0 ? 3 : 2)
                .foregroundStyle(textColor(level: node.level, color: color))

            if node.level == 1, concept != nil {
                Text(importance.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(node.level == 1 ? Color.white.opacity(0.85) : importanceColor(importance))
            }
        }
        .padding(.horizontal, horizontalPadding(for: node.level))
        .padding(.vertical, verticalPadding(for: node.level))
        .frame(maxWidth: maxWidth(for: node.level))
        .background {
            RoundedRectangle(cornerRadius: cornerRadius(for: node.level), style: .continuous)
                .fill(nodeBackground(level: node.level, color: color))
                .shadow(color: .black.opacity(isSelected ? 0.22 : 0.08), radius: isSelected ? 12 : 4, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius(for: node.level), style: .continuous)
                .strokeBorder(
                    isSelected ? color : strokeColor(level: node.level, color: color),
                    lineWidth: isSelected ? 2.5 : (node.level == 2 ? 1.5 : 1)
                )
        }
        .scaleEffect(isSelected ? 1.06 : 1)
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
    
    private func fitToView(viewSize: CGSize) {
        let layout = layout
        guard
            layout.bounds.width > 0, layout.bounds.height > 0,
            viewSize.width > 0, viewSize.height > 0
        else { return }

        let fitScale = min(
            viewSize.width / layout.bounds.width,
            viewSize.height / layout.bounds.height
        ) * 0.92

        // The whole content group (including labels) scales as one, so fitting
        // never overlaps siblings — the worst case is small-but-readable text
        // the user can scroll-zoom into. Centering is handled by the enclosing
        // ZStack, so fit only sets the scale and clears any pan.
        scale = min(max(fitScale, 0.18), 1.25)
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
    
    // MARK: - Branch colour coding

    /// Distinct, legible-in-both-appearances hues. One per colour family; the
    /// map cycles through them if a graph has more branches than colours.
    private static let branchPalette: [Color] = [
        Color(red: 0.91, green: 0.30, blue: 0.39),  // rose
        Color(red: 0.96, green: 0.55, blue: 0.18),  // orange
        Color(red: 0.83, green: 0.66, blue: 0.11),  // gold
        Color(red: 0.30, green: 0.70, blue: 0.42),  // green
        Color(red: 0.16, green: 0.64, blue: 0.71),  // teal
        Color(red: 0.27, green: 0.53, blue: 0.92),  // blue
        Color(red: 0.51, green: 0.42, blue: 0.91),  // indigo
        Color(red: 0.80, green: 0.40, blue: 0.78),  // magenta
    ]

    private func branchColor(for nodeId: String) -> Color {
        guard let index = layout.branchIndex[nodeId], index >= 0 else {
            return Color(red: 0.55, green: 0.57, blue: 0.62)  // neutral slate
        }
        return Self.branchPalette[index % Self.branchPalette.count]
    }

    /// The set of nodes connected to the selection by ancestry or descent. Nil
    /// when nothing is selected, meaning "show everything at full strength".
    private var focusLineage: Set<String>? {
        guard let selectedNodeId else { return nil }

        var parents: [String: [String]] = [:]
        var children: [String: [String]] = [:]
        for edge in layout.displayEdges {
            parents[edge.toId, default: []].append(edge.fromId)
            children[edge.fromId, default: []].append(edge.toId)
        }

        var related: Set<String> = [selectedNodeId]
        func walk(from start: String, _ adjacency: [String: [String]]) {
            var stack = [start]
            while let current = stack.popLast() {
                for next in adjacency[current] ?? [] where !related.contains(next) {
                    related.insert(next)
                    stack.append(next)
                }
            }
        }
        walk(from: selectedNodeId, parents)
        walk(from: selectedNodeId, children)
        return related
    }

    private func nodeBackground(level: Int, color: Color) -> AnyShapeStyle {
        switch level {
        case 0:
            // The root topic keeps a fixed warm identity, not a branch hue.
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.pink, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case 1:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [color, color.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        default:
            return AnyShapeStyle(color.opacity(0.14))
        }
    }

    private func textColor(level: Int, color: Color) -> Color {
        switch level {
        case 0, 1: return .white
        default: return color
        }
    }

    private func strokeColor(level: Int, color: Color) -> Color {
        level == 2 ? color.opacity(0.55) : Color.primary.opacity(0.08)
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
    var onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelZoomNSView {
        let view = ScrollWheelZoomNSView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: ScrollWheelZoomNSView, context: Context) {
        nsView.onZoom = onZoom
    }

    static func dismantleNSView(_ nsView: ScrollWheelZoomNSView, coordinator: ()) {
        nsView.teardown()
    }
}

/// Captures scroll-wheel / trackpad scroll over the canvas and turns it into a
/// zoom factor. A local event monitor is used instead of `scrollWheel(with:)`
/// because this view sits in SwiftUI's `.background`, behind the hosting view
/// that would otherwise swallow the event — the monitor sees it regardless of
/// z-order, scoped to events landing inside this view's bounds.
private final class ScrollWheelZoomNSView: NSView {
    var onZoom: ((CGFloat) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            teardown()
        } else {
            install()
        }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard
                let self,
                let window = self.window,
                event.window === window
            else { return event }

            let pointInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(pointInView) else { return event }

            let factor: CGFloat
            if event.hasPreciseScrollingDeltas {
                // Trackpad: proportional to the swipe so it feels continuous.
                guard event.scrollingDeltaY != 0 else { return event }
                factor = exp(event.scrollingDeltaY * 0.004)
            } else {
                // Mouse wheel: fixed step per notch.
                guard event.scrollingDeltaY != 0 || event.deltaY != 0 else { return event }
                let up = (event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY) > 0
                factor = up ? 1.1 : 0.9
            }

            self.onZoom?(factor)
            return nil  // consume so the surrounding view doesn't also scroll
        }
    }

    func teardown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { teardown() }
}
