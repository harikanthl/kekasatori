//
//  StudyToolsPanel.swift
//  MuseDrop
//

import SwiftUI
import AppKit

struct StudyToolsPanel: View {
    let item: DownloadItem
    @ObservedObject var viewModel: PlayerViewModel
    
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            statusStrip
            generationProgressBar
            
            if viewModel.showStoppedGenerationPrompt {
                stoppedGenerationBanner
                    .padding(.horizontal, StudyPanelDesign.contentPadding)
                    .padding(.top, 8)
            }
            
            if let error = viewModel.aiError {
                errorBanner(error)
                    .padding(.horizontal, StudyPanelDesign.contentPadding)
                    .padding(.top, 8)
            }
            
            StudyTabBar(tabs: availableStudyTabs, selection: $viewModel.selectedStudyTab)
            SectionRule()

            translationBar

            tabBody
        }
        .studyTranslationHost(viewModel.translationCoordinator)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task { @MainActor in
                if viewModel.analysis == nil, viewModel.selectedStudyTab.requiresStudyPack {
                    viewModel.selectedStudyTab = .canvas
                }
            }
        }
    }
    
    // MARK: - Chrome
    
    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Study")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(StudyPanelDesign.accent)
                
                Text(viewModel.aiEngineDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            headerAction
        }
        .padding(StudyPanelDesign.headerPadding)
    }
    
    @ViewBuilder
    private var headerAction: some View {
        if viewModel.isGeneratingAI {
            HStack(spacing: 8) {
                if viewModel.isTranscriptionPhase {
                    if viewModel.isGenerationPaused {
                        Button { viewModel.resumeGeneration() } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Resume")
                    } else {
                        Button { viewModel.pauseGeneration() } label: {
                            Image(systemName: "pause.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Pause")
                    }
                }
                
                Button(role: .destructive) { viewModel.stopGeneration() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help("Stop")
            }
        } else {
            Button {
                viewModel.generateStudyMaterials(
                    for: item,
                    forceRegenerate: viewModel.analysis != nil || viewModel.hasSavedTranscript
                )
            } label: {
                Label(
                    viewModel.analysis == nil ? "Generate" : "Regenerate",
                    systemImage: "arrow.trianglehead.2.counterclockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(StudyPanelDesign.accent)
            .controlSize(.regular)
            .disabled(!SettingsViewModel.isAIEnabled)
            .help(generateButtonHelp)
        }
    }
    
    private var generateButtonHelp: String {
        if viewModel.analysis != nil {
            return "Rebuild summary, notes, and cards from your saved transcript"
        }
        if viewModel.hasSavedTranscript {
            return "Generate study pack from saved transcript"
        }
        return "Transcribe and generate a full study pack"
    }
    
    @ViewBuilder
    private var statusStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if viewModel.analysis != nil {
                    StudyStatusChip(title: "Pack saved", icon: "checkmark.circle.fill", tint: .green)
                }
                
                if viewModel.hasSavedTranscript || viewModel.analysis != nil {
                    StudyStatusChip(title: "Transcript", icon: "doc.text")
                }
                
                if let duration = MediaSourceIdentity.formatDuration(item.durationSeconds) {
                    StudyStatusChip(title: duration, icon: "clock")
                }
                
                if let transcript = viewModel.analysis?.transcript ?? viewModel.savedTranscript {
                    StudyStatusChip(
                        title: transcript.text.count.formatted() + " chars",
                        icon: "character.cursor.ibeam"
                    )
                }
                
                if viewModel.lastAnalysisEngine == .naturalLanguageFallback {
                    StudyStatusChip(title: "Fallback engine", icon: "exclamationmark.triangle.fill", tint: .orange)
                } else if SettingsViewModel.isWebResearchEnabled {
                    StudyStatusChip(title: "Web research", icon: "globe")
                }
            }
            .padding(.horizontal, StudyPanelDesign.contentPadding)
            .padding(.bottom, 8)
        }
    }
    
    @ViewBuilder
    private var generationProgressBar: some View {
        if viewModel.isGeneratingAI {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView()
                    .progressViewStyle(.linear)
                
                Text(viewModel.aiProgressDetail ?? "Transcribing and analyzing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, StudyPanelDesign.contentPadding)
            .padding(.bottom, 10)
        }
    }
    
    /// Drives the retro status bar inside the translation area.
    private var translationStatus: RetroStatus? {
        if viewModel.isTranslating {
            let into = viewModel.translatingLanguageName.map { " into \($0)" } ?? ""
            return RetroStatus(
                kind: .working,
                message: "summary · notes · cards · terms\(into)"
            )
        }
        if let error = viewModel.translationError {
            return RetroStatus(kind: .warning, message: error)
        }
        return nil
    }

    @ViewBuilder
    private var translationBar: some View {
        let hasContent = viewModel.analysis != nil || viewModel.hasSavedTranscript
        let isTranslatableTab = ![.tutor, .canvas, .notebook].contains(viewModel.selectedStudyTab)

        if hasContent, isTranslatableTab, !viewModel.isGeneratingAI {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(TranslationLanguageOption.common) { option in
                            Button(option.displayName) {
                                Task { await viewModel.translatePack(to: option) }
                            }
                        }
                    } label: {
                        Label("Translate", systemImage: "character.bubble")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(viewModel.isTranslating)

                    if viewModel.transcriptIsNonEnglish {
                        Button {
                            Task { await viewModel.translateTranscriptToEnglishAndRegenerate(for: item) }
                        } label: {
                            Label("To English & regenerate", systemImage: "globe")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(viewModel.isTranslating)
                        .help("Translate the transcript to English, then rebuild the study pack in English")
                    }

                    Spacer(minLength: 4)

                    if !viewModel.isTranslating, let language = viewModel.activeTranslationDisplayName {
                        HStack(spacing: 6) {
                            StudyStatusChip(title: language, icon: "character.bubble.fill", tint: StudyPanelDesign.accent)
                            Button("Show original") { viewModel.clearTranslation() }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                    }
                }

                RetroStatusBar(status: translationStatus)
            }
            .padding(.horizontal, StudyPanelDesign.contentPadding)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

            Divider()
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        if viewModel.selectedStudyTab == .tutor {
            TutorChatView(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedStudyTab == .canvas {
            CanvasStudyView(
                item: item,
                analysis: viewModel.analysis,
                fillsAvailableSpace: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.selectedStudyTab == .notebook {
            NotebookStudyView(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let analysis = viewModel.displayedAnalysis {
                        studyTabContent(analysis: analysis)
                    } else if let transcript = viewModel.displayedTranscript {
                        studyTabContent(analysis: nil, transcript: transcript)
                    } else if !viewModel.isGeneratingAI && viewModel.aiError == nil {
                        emptyState
                    }
                    
                    if !viewModel.artifactHistory.isEmpty {
                        historySection
                    }
                }
                .padding(StudyPanelDesign.contentPadding)
            }
        }
    }
    
    private var historySection: some View {
        DisclosureGroup(isExpanded: $showHistory) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(dedupedArtifactHistory.prefix(6)) { entry in
                    HStack {
                        Text(artifactHistoryLabel(for: entry.kindRaw))
                            .font(.caption)
                        Spacer()
                        Text(entry.generatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Generation history")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
    
    private var dedupedArtifactHistory: [StudyArtifactHistoryItem] {
        var latestByKind: [String: StudyArtifactHistoryItem] = [:]
        for entry in viewModel.artifactHistory {
            if let existing = latestByKind[entry.kindRaw] {
                if entry.generatedAt > existing.generatedAt {
                    latestByKind[entry.kindRaw] = entry
                }
            } else {
                latestByKind[entry.kindRaw] = entry
            }
        }
        return latestByKind.values.sorted { $0.generatedAt > $1.generatedAt }
    }
    
    private func artifactHistoryLabel(for kindRaw: String) -> String {
        switch kindRaw {
        case AIStudyArtifactKind.fullPack.rawValue: return "Full pack"
        case AIStudyArtifactKind.transcript.rawValue: return "Transcript"
        case AIStudyArtifactKind.regenerated.rawValue: return "Regenerated"
        case AIStudyArtifactKind.summary.rawValue: return "Summary"
        default: return kindRaw
        }
    }
    
    private var availableStudyTabs: [AIStudyTab] {
        // Tutor is always available (works on any item, no study pack needed).
        if viewModel.analysis != nil {
            return AIStudyTab.allCases
        }
        if viewModel.hasSavedTranscript {
            return [.tutor, .canvas, .notebook, .transcript]
        }
        return [.tutor, .canvas, .notebook]
    }
    
    @ViewBuilder
    private func studyTabContent(analysis: MediaAnalysis?, transcript: MediaTranscript? = nil) -> some View {
        switch viewModel.selectedStudyTab {
        case .tutor, .canvas, .notebook:
            EmptyView()
        case .transcript:
            if let analysis {
                rawTranscriptView(analysis.transcript)
            } else if let transcript {
                rawTranscriptView(transcript)
            }
        default:
            if let analysis {
                legacyTabContent(for: analysis)
            } else {
                lockedTabPlaceholder
            }
        }
    }
    
    private var lockedTabPlaceholder: some View {
        ContentPlaceholder(
            icon: "lock.fill",
            title: "Study pack required",
            message: "Generate a study pack to unlock \(viewModel.selectedStudyTab.rawValue.lowercased())."
        )
    }
    
    @ViewBuilder
    private func legacyTabContent(for analysis: MediaAnalysis) -> some View {
        switch viewModel.selectedStudyTab {
        case .tutor, .canvas, .notebook, .transcript:
            EmptyView()
        case .summary:
            summaryView(analysis.summary)
        case .notes:
            notesView(analysis.notes)
        case .flashcards:
            flashcardsView(analysis.flashcards)
        case .mindMap:
            mindMapView(analysis.mindMap, concepts: analysis.keyConcepts)
        case .concepts:
            conceptsView(analysis.keyConcepts)
        }
    }
    
    private var stoppedGenerationBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Generation stopped", systemImage: "stop.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            
            if viewModel.stoppedGenerationHasPartialData {
                Text("Partial data was saved. Delete it or keep it for a later retry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        viewModel.deletePartialStudyData(for: item)
                    } label: {
                        Text("Delete")
                    }
                    .controlSize(.small)
                    
                    Button { viewModel.dismissStoppedGenerationPrompt() } label: {
                        Text("Keep")
                    }
                    .controlSize(.small)
                }
            } else {
                Text(viewModel.analysis != nil ? "Your saved study pack was not changed." : "No study data was saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button { viewModel.dismissStoppedGenerationPrompt() } label: {
                    Text("Dismiss")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: StudyPanelDesign.cornerRadius, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        }
    }
    
    private var emptyState: some View {
        ContentPlaceholder(
            icon: "text.book.closed",
            title: "No study materials yet",
            message: "Tap Generate to create summary, notes, flashcards, and concept maps from this video."
        )
    }
    
    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(StudyPanelDesign.accent)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: StudyPanelDesign.cornerRadius, style: .continuous)
                    .fill(StudyPanelDesign.accent.opacity(0.08))
            }
    }
    
    // MARK: - Transcript
    
    private func rawTranscriptView(_ transcript: MediaTranscript) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                Spacer()
                copyButton(text: transcript.text)
            }
            
            transcriptMetadataRow(transcript)
            
            ScrollView {
                Text(transcript.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 280)
            .padding(12)
            .background(contentSurface)
        }
        .padding(14)
        .background(cardBackground)
    }
    
    private func transcriptMetadataRow(_ transcript: MediaTranscript) -> some View {
        HStack(spacing: 8) {
            if let coverage = transcript.coverageNote, !coverage.isEmpty {
                Text(coverage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let transcriptDuration = MediaSourceIdentity.formatDuration(transcript.sourceDurationSeconds) {
                Text("Covers \(transcriptDuration)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Summary
    
    private func summaryView(_ summary: SummaryResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.oneLine)
                .font(.subheadline.weight(.semibold))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(contentSurface)
            
            Text(summary.paragraph)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            if !summary.bullets.isEmpty {
                bulletList(summary.bullets, title: "Key points")
            }
            
            copyButton(text: exportSummary(summary))
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Notes
    
    private func notesView(_ notes: StudyNotes) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(notes.title)
                .font(.headline)
            
            ForEach(notes.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.heading)
                        .font(.subheadline.weight(.semibold))
                    
                    if !section.content.isEmpty {
                        Text(section.content)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    if !section.bullets.isEmpty {
                        bulletList(section.bullets)
                    }
                }
                
                if section.id != notes.sections.last?.id {
                    Divider()
                }
            }
            
            copyButton(text: exportNotes(notes))
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Flashcards
    
    private func flashcardsView(_ cards: [FlashCard]) -> some View {
        VStack(spacing: 12) {
            if cards.isEmpty {
                Text("No flashcards generated.")
                    .foregroundStyle(.secondary)
            } else {
                let card = cards[viewModel.flashcardIndex]
                
                StudyFlashcardSession(
                    front: card.front,
                    back: card.back,
                    tag: card.tag,
                    index: viewModel.flashcardIndex,
                    total: cards.count,
                    isShowingBack: viewModel.showingFlashcardBack,
                    onFlip: { viewModel.toggleFlashcardSide() },
                    onPrevious: { viewModel.previousFlashcard() },
                    onNext: { viewModel.nextFlashcard() }
                )
                .animation(.easeInOut(duration: 0.2), value: viewModel.flashcardIndex)
                
                copyButton(text: exportFlashcards(cards))
            }
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Mind Map
    
    private func mindMapView(_ mindMap: MindMap, concepts: [KeyConcept]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tap nodes for definitions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ConceptGraphCanvasView(mindMap: mindMap, concepts: concepts)
            
            copyButton(text: exportMindMap(mindMap))
        }
        .padding(14)
        .background(cardBackground)
    }
    
    // MARK: - Concepts
    
    // Terms are a definitions list only — the relationship graph lives in the
    // Mind Map tab, so it isn't duplicated here.
    private func conceptsView(_ concepts: [KeyConcept]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            conceptsListView(concepts)
            copyButton(text: exportConcepts(concepts))
        }
        .padding(14)
        .background(cardBackground)
    }
    
    private func conceptsListView(_ concepts: [KeyConcept]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(concepts) { concept in
                VStack(alignment: .leading, spacing: 4) {
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
                .padding(10)
                .background(contentSurface)
            }
        }
    }
    
    // MARK: - Shared UI
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: StudyPanelDesign.cornerRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }
    
    private var contentSurface: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
    }
    
    private func bulletList(_ items: [String], title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(items, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(StudyPanelDesign.accent.opacity(0.7))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(bullet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private func importanceBadge(_ importance: String) -> some View {
        Text(importance.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(importanceColor(importance).opacity(0.14)))
            .foregroundStyle(importanceColor(importance))
    }
    
    private func importanceColor(_ importance: String) -> Color {
        switch importance.lowercased() {
        case "high": return StudyPanelDesign.accent
        case "medium": return .orange
        default: return .secondary
        }
    }
    
    private func copyButton(text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    // MARK: - Export
    
    private func exportSummary(_ summary: SummaryResult) -> String {
        """
        \(summary.oneLine)
        
        \(summary.paragraph)
        
        \(summary.bullets.map { "• \($0)" }.joined(separator: "\n"))
        """
    }
    
    private func exportNotes(_ notes: StudyNotes) -> String {
        var text = "\(notes.title)\n\n"
        for section in notes.sections {
            text += "## \(section.heading)\n"
            if !section.content.isEmpty { text += "\(section.content)\n" }
            for bullet in section.bullets { text += "• \(bullet)\n" }
            text += "\n"
        }
        return text
    }
    
    private func exportFlashcards(_ cards: [FlashCard]) -> String {
        cards.enumerated().map { index, card in
            "Card \(index + 1)\nQ: \(card.front)\nA: \(card.back)\n"
        }.joined(separator: "\n")
    }
    
    private func exportMindMap(_ mindMap: MindMap) -> String {
        var text = "Central: \(mindMap.centralTopic)\n"
        for node in mindMap.primaryNodes {
            text += "\n- \(node.label)\n"
            for child in mindMap.children(of: node.id) {
                text += "  • \(child.label)\n"
            }
        }
        return text
    }
    
    private func exportConcepts(_ concepts: [KeyConcept]) -> String {
        concepts.map { "\($0.term) (\($0.importance)): \($0.definition)" }.joined(separator: "\n\n")
    }
}

// MARK: - Placeholder

private struct ContentPlaceholder: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: StudyPanelDesign.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        }
    }
}
