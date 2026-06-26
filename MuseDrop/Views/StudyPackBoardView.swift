//
//  StudyPackBoardView.swift
//  Kekasatori
//
//  A Kanban-style board for study packs, organized by Shu-Ha-Ri mastery.
//  Drag a card between columns to change its stage; tap to open. Honors the
//  view model's active search/filter (it reads `filteredPacks`).
//

import SwiftUI

struct StudyPackBoardView: View {
    @ObservedObject var viewModel: StudyPackHistoryViewModel
    let onOpen: (StudyPackSummary) -> Void

    private struct Column: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let stage: MasteryStage?   // nil == "To Study" (unset)
        let tint: Color
    }

    private var boardColumns: [Column] {
        [
            Column(id: "todo", title: "To Study", subtitle: nil, stage: nil, tint: .secondary),
            Column(id: "shu", title: "Learning", subtitle: "Shu", stage: .learning, tint: MasteryStage.learning.tint),
            Column(id: "ha", title: "Practicing", subtitle: "Ha", stage: .practicing, tint: MasteryStage.practicing.tint),
            Column(id: "ri", title: "Mastered", subtitle: "Ri", stage: .mastered, tint: MasteryStage.mastered.tint),
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ForEach(boardColumns) { column in
                    columnView(column)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.md)
        }
    }

    private func packs(in column: Column) -> [StudyPackSummary] {
        viewModel.filteredPacks.filter { $0.masteryStage == column.stage }
    }

    private func columnView(_ column: Column) -> some View {
        let items = packs(in: column)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Circle().fill(column.tint).frame(width: 8, height: 8)
                Text(column.title).font(.subheadline.weight(.semibold))
                if let subtitle = column.subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if items.isEmpty {
                Text("Drop packs here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 64)
            } else {
                ForEach(items) { pack in
                    card(pack, tint: column.tint)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 220, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let first = ids.first,
                  let uuid = UUID(uuidString: first),
                  let pack = viewModel.packs.first(where: { $0.downloadId == uuid })
            else { return false }
            guard pack.masteryStage != column.stage else { return false }
            withAnimation(.snappy(duration: 0.25)) {
                viewModel.setMastery(column.stage, for: pack)
            }
            return true
        }
    }

    private func card(_ pack: StudyPackSummary, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                if pack.isPinned {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.20))
                }
                Text(pack.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 10) {
                if pack.flashcardCount > 0 {
                    miniStat("\(pack.flashcardCount)", "rectangle.on.rectangle.angled")
                }
                if pack.noteSectionCount > 0 {
                    miniStat("\(pack.noteSectionCount)", "note.text")
                }
                if pack.conceptCount > 0 {
                    miniStat("\(pack.conceptCount)", "lightbulb")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(pack) }
        .draggable(pack.downloadId.uuidString) {
            // A flat, opaque preview — the default snapshot of the styled card
            // (material + stroke + shadow) is heavy and trails the cursor.
            Text(pack.displayTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 200)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
        }
        .contextMenu {
            Button("Open") { onOpen(pack) }
            Button(pack.isPinned ? "Unpin" : "Pin to top") { viewModel.togglePin(for: pack) }
        }
    }

    private func miniStat(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(text)
        }
    }
}
