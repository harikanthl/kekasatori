//
//  ActiveContextBar.swift
//  MuseDrop
//
//  A persistent, app-wide indicator of what you're working on — the active
//  workspace and the compute target the dial is set to (with live $/hr). Reuses
//  the retro terminal chrome (`retroBarChrome` + blinking `RetroPrompt`) from
//  RetroStatusBar so it reads as one family. Unlike the ephemeral status bar this
//  is always present and reflects shared state (WorkspaceStore / ComputeTargetStore).
//

import SwiftUI

struct ActiveContextBar: View {
    @ObservedObject private var workspaces = WorkspaceStore.shared
    @ObservedObject private var targets = ComputeTargetStore.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            RetroPrompt(paused: reduceMotion, tint: theme.accent)

            segment(icon: "square.grid.2x2", text: workspaces.selected?.title ?? "no workspace")
            Text("·").foregroundStyle(.white.opacity(0.4))
            segment(icon: targetIcon, text: targets.selected?.name ?? "no compute")

            if let rate = ComputeCost.ratePerHour(targets.selected?.capabilities.costPerHourUSD) {
                Text(rate).foregroundStyle(VintageDial.amber)
            }

            Spacer(minLength: 0)
        }
        .font(.system(.caption, design: .monospaced).weight(.medium))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroBarChrome(tint: theme.accent)
        .accessibilityElement()
        .accessibilityLabel("Working on \(workspaces.selected?.title ?? "no workspace"), compute \(targets.selected?.name ?? "none")")
    }

    private var targetIcon: String {
        (targets.selected?.isPaid ?? false) ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent"
    }

    private func segment(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(text)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}
