//
//  ConceptGraphLayout.swift
//  MuseDrop
//
//  Radial seeding + collision relaxation so nodes never overlap regardless of
//  count. Spacing is derived from node label widths and the graph fits the
//  canvas without being clamped into a squished, overlapping pile.
//

import CoreGraphics
import Foundation

enum ConceptGraphLayout {
    struct LayoutResult {
        var positions: [String: CGPoint]
        var bounds: CGRect
        var displayNodes: [MindMapNode]
        var displayEdges: [MindMapEdge]
        /// Which colour family a node belongs to. Every level-1 node starts a
        /// branch; its whole subtree inherits the same index. Center and any
        /// unrooted nodes are `-1` (neutral). Drives the map's colour coding.
        var branchIndex: [String: Int] = [:]
    }

    /// Minimum center-to-center distance between any two nodes. Exceeds the
    /// widest node label so a uniform zoom can never make siblings overlap.
    private static let minNodeDistance: CGFloat = 200

    static func layout(mindMap: MindMap, concepts: [KeyConcept]) -> LayoutResult {
        if mindMap.nodes.isEmpty, !concepts.isEmpty {
            return layoutConceptsOnly(concepts: concepts, centralTopic: mindMap.centralTopic)
        }
        return layoutMindMap(mindMap)
    }

    private static func layoutMindMap(_ mindMap: MindMap) -> LayoutResult {
        guard !mindMap.nodes.isEmpty else {
            return LayoutResult(
                positions: [:],
                bounds: CGRect(x: 0, y: 0, width: 400, height: 280),
                displayNodes: [],
                displayEdges: []
            )
        }

        let centerNode = mindMap.nodes.first(where: { $0.level == 0 })
            ?? MindMapNode(id: "center", label: mindMap.centralTopic, level: 0)

        var positions: [String: CGPoint] = [:]
        let origin = CGPoint.zero
        positions[centerNode.id] = origin

        let primary = mindMap.nodes.filter { $0.level == 1 }
        // Radius sized so primary siblings are at least minNodeDistance apart
        // along the ring's circumference (count * spacing = 2πr).
        let primaryRadius = ringRadius(count: primary.count, minimum: 210)

        for (index, node) in primary.enumerated() {
            let angle = (2 * CGFloat.pi * CGFloat(index) / CGFloat(max(primary.count, 1))) - (.pi / 2)
            let parentPoint = CGPoint(
                x: origin.x + primaryRadius * cos(angle),
                y: origin.y + primaryRadius * sin(angle)
            )
            positions[node.id] = parentPoint

            let children = mindMap.children(of: node.id)
            // Far enough out that a child never overlaps its parent (half-widths
            // of parent + child ≈ 154pt), and relaxation handles the rest. Busy
            // branches push their children farther so the fan never crowds.
            let childRadius: CGFloat = 175 + CGFloat(max(0, children.count - 2)) * 14
            let spread = min(CGFloat.pi / 2.0, CGFloat.pi / CGFloat(max(children.count, 1)) * 1.15)

            for (childIndex, child) in children.enumerated() {
                let offset = spread * (CGFloat(childIndex) - CGFloat(children.count - 1) / 2)
                let childAngle = angle + offset
                positions[child.id] = CGPoint(
                    x: parentPoint.x + childRadius * cos(childAngle),
                    y: parentPoint.y + childRadius * sin(childAngle)
                )
            }
        }

        // Any node not reached by the hierarchy goes on a ring outside the
        // primary ring so it can't land on top of existing nodes.
        let orphanRadius = primaryRadius + 240
        let orphans = mindMap.nodes.filter { positions[$0.id] == nil }
        for (index, node) in orphans.enumerated() {
            let angle = (2 * CGFloat.pi * CGFloat(index) / CGFloat(max(orphans.count, 1)))
            positions[node.id] = CGPoint(x: orphanRadius * cos(angle), y: orphanRadius * sin(angle))
        }

        relax(positions: &positions, pinned: centerNode.id)

        let branchIndex = computeBranchIndex(
            edges: mindMap.edges,
            center: centerNode.id,
            primary: primary
        )

        return normalizedLayout(
            positions: positions,
            nodes: mindMap.nodes,
            edges: mindMap.edges,
            branchIndex: branchIndex,
            padding: 110
        )
    }

    private static func layoutConceptsOnly(concepts: [KeyConcept], centralTopic: String) -> LayoutResult {
        let center = MindMapNode(id: "center", label: centralTopic.isEmpty ? "Key Concepts" : centralTopic, level: 0)
        var nodes: [MindMapNode] = [center]
        var edges: [MindMapEdge] = []
        var positions: [String: CGPoint] = [center.id: .zero]

        var branchIndex: [String: Int] = [center.id: -1]
        let radius = ringRadius(count: concepts.count, minimum: 200)
        for (index, concept) in concepts.enumerated() {
            let node = MindMapNode(id: concept.id, label: concept.term, level: 1)
            nodes.append(node)
            edges.append(MindMapEdge(fromId: center.id, toId: node.id, relationship: concept.importance))
            // Concepts-only maps have no sub-tree, so each term is its own family.
            branchIndex[node.id] = index

            let angle = (2 * CGFloat.pi * CGFloat(index) / CGFloat(max(concepts.count, 1))) - (.pi / 2)
            positions[node.id] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }

        relax(positions: &positions, pinned: center.id)

        return normalizedLayout(
            positions: positions,
            nodes: nodes,
            edges: edges,
            branchIndex: branchIndex,
            padding: 100
        )
    }

    /// Assigns every node the colour-family index of the level-1 ancestor it
    /// descends from. A node reachable from several branches keeps the first
    /// (by primary order) that claims it; the center and unrooted nodes stay -1.
    private static func computeBranchIndex(
        edges: [MindMapEdge],
        center: String,
        primary: [MindMapNode]
    ) -> [String: Int] {
        var childMap: [String: [String]] = [:]
        for edge in edges where edge.toId != center {
            childMap[edge.fromId, default: []].append(edge.toId)
        }

        var index: [String: Int] = [center: -1]
        for (branch, node) in primary.enumerated() {
            var stack = [node.id]
            while let current = stack.popLast() {
                guard index[current] == nil else { continue }
                index[current] = branch
                for child in childMap[current] ?? [] where index[child] == nil {
                    stack.append(child)
                }
            }
        }
        return index
    }

    /// Radius such that `count` nodes spaced `minNodeDistance` apart fit on the
    /// ring circumference, never smaller than `minimum`.
    private static func ringRadius(count: Int, minimum: CGFloat) -> CGFloat {
        guard count > 1 else { return minimum }
        let circumferenceRadius = CGFloat(count) * minNodeDistance / (2 * .pi)
        return max(minimum, circumferenceRadius)
    }

    /// Iteratively pushes apart any two nodes closer than `minNodeDistance`.
    /// The pinned node (graph center) never moves; its neighbours absorb the
    /// full correction so the hub stays put.
    private static func relax(
        positions: inout [String: CGPoint],
        pinned: String,
        iterations: Int = 80
    ) {
        // Sorted so relaxation is deterministic — dictionary key order is not
        // stable, which would otherwise drift the layout between rebuilds.
        let ids = positions.keys.sorted()
        guard ids.count > 1 else { return }
        let minDistance = minNodeDistance

        for _ in 0..<iterations {
            var moved = false
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    let idA = ids[i], idB = ids[j]
                    guard let a = positions[idA], let b = positions[idB] else { continue }
                    var dx = b.x - a.x
                    var dy = b.y - a.y
                    var dist = (dx * dx + dy * dy).squareRoot()
                    if dist < 0.001 {
                        // Coincident: nudge deterministically by index so they separate.
                        dx = CGFloat(j - i)
                        dy = CGFloat(i + 1)
                        dist = (dx * dx + dy * dy).squareRoot()
                    }
                    guard dist < minDistance else { continue }
                    let overlap = minDistance - dist
                    let ux = dx / dist
                    let uy = dy / dist
                    let aPinned = idA == pinned
                    let bPinned = idB == pinned
                    if aPinned && bPinned { continue }
                    if aPinned {
                        positions[idB] = CGPoint(x: b.x + ux * overlap, y: b.y + uy * overlap)
                    } else if bPinned {
                        positions[idA] = CGPoint(x: a.x - ux * overlap, y: a.y - uy * overlap)
                    } else {
                        let half = overlap / 2
                        positions[idA] = CGPoint(x: a.x - ux * half, y: a.y - uy * half)
                        positions[idB] = CGPoint(x: b.x + ux * half, y: b.y + uy * half)
                    }
                    moved = true
                }
            }
            if !moved { break }
        }
    }

    private static func normalizedLayout(
        positions: [String: CGPoint],
        nodes: [MindMapNode],
        edges: [MindMapEdge],
        branchIndex: [String: Int],
        padding: CGFloat
    ) -> LayoutResult {
        guard !positions.isEmpty else {
            return LayoutResult(
                positions: [:],
                bounds: CGRect(x: 0, y: 0, width: 400, height: 280),
                displayNodes: nodes,
                displayEdges: edges,
                branchIndex: branchIndex
            )
        }

        let xs = positions.values.map(\.x)
        let ys = positions.values.map(\.y)
        let minX = (xs.min() ?? 0) - padding
        let minY = (ys.min() ?? 0) - padding
        let maxX = (xs.max() ?? 0) + padding
        let maxY = (ys.max() ?? 0) + padding

        let shifted = positions.mapValues { point in
            CGPoint(x: point.x - minX, y: point.y - minY)
        }

        let bounds = CGRect(x: 0, y: 0, width: maxX - minX, height: maxY - minY)
        return LayoutResult(
            positions: shifted,
            bounds: bounds,
            displayNodes: nodes,
            displayEdges: edges,
            branchIndex: branchIndex
        )
    }
}
