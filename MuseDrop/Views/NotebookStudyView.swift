//
//  NotebookStudyView.swift
//  MuseDrop
//

import SwiftUI

struct NotebookStudyView: View {
    let item: DownloadItem
    
    @StateObject private var viewModel: NotebookViewModel
    @State private var selectedText: String = ""
    @State private var showAnimationStudio = false
    @State private var expandAnimationId: UUID?
    @StateObject private var animationViewModel: NotebookAnimationViewModel
    
    init(item: DownloadItem) {
        self.item = item
        _viewModel = StateObject(
            wrappedValue: NotebookViewModel(
                downloadId: item.id,
                mediaTitle: item.displayTitle
            )
        )
        _animationViewModel = StateObject(
            wrappedValue: NotebookAnimationViewModel(
                downloadId: item.id,
                dayKey: NotebookDayKey.today(),
                mediaTitle: item.displayTitle
            )
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            notebookHeader
            daySelector
            Divider()
            
            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading notebook…")
                    .controlSize(.regular)
                Spacer()
            } else {
                VStack(spacing: 0) {
                    NotebookFormattingToolbar(
                        formatting: Binding(
                            get: { viewModel.pageFormatting },
                            set: { viewModel.updateFormatting($0) }
                        )
                    ) { command in
                        viewModel.sendFormatCommand(command)
                    }
                    
                    Divider()
                    
                    ScrollViewReader { proxy in
                        GeometryReader { geo in
                            ScrollView {
                                VStack(spacing: 14) {
                                    ZStack(alignment: .bottomTrailing) {
                                        NotebookPageView(
                                            template: viewModel.selectedTemplate,
                                            plainText: viewModel.editorText,
                                            richContent: viewModel.richContent,
                                            formatting: Binding(
                                                get: { viewModel.pageFormatting },
                                                set: { viewModel.updateFormatting($0) }
                                            ),
                                            formatCommand: Binding(
                                                get: { viewModel.formatCommand },
                                                set: { viewModel.formatCommand = $0 }
                                            ),
                                            onContentChange: { text, rich in
                                                viewModel.updateEditorContent(text: text, richContent: rich)
                                            },
                                            onSelectionChange: { selectedText = $0 }
                                        )
                                        // Fill the pane: when there are no animations the page
                                        // covers the whole right pane; when there are, it stays
                                        // large and leaves a peek of the gallery below.
                                        .frame(minHeight: pageMinHeight(available: geo.size.height))
                                        .id(viewModel.selectedTemplate)

                                        if canQuickAnimate {
                                            quickAnimatePill
                                                .padding(16)
                                        }
                                    }

                                    if !animationViewModel.animations.isEmpty {
                                        NotebookInlineAnimationsView(
                                            downloadId: item.id,
                                            dayKey: viewModel.selectedDayKey,
                                            animations: animationViewModel.animations,
                                            autoPlayId: expandAnimationId,
                                            onDelete: { record in
                                                Task { await animationViewModel.delete(record) }
                                            }
                                        )
                                        .id("inline-animations")
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.bottom, 12)
                            }
                            .onChange(of: animationViewModel.animations.count) { _, _ in
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo("inline-animations", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadEntries()
            syncAnimationContext()
        }
        .onChange(of: viewModel.selectedDayKey) { _, newDayKey in
            animationViewModel.dayKey = newDayKey
            animationViewModel.loadAnimations()
            animationViewModel.stopPreview()
        }
        .onDisappear {
            Task { await viewModel.flushSave() }
            animationViewModel.stopPreview()
        }
        .sheet(isPresented: $showAnimationStudio) {
            NotebookAnimationStudio(viewModel: animationViewModel) {
                showAnimationStudio = false
            } onRendered: { record in
                animationViewModel.loadAnimations()
                showAnimationStudio = false
                expandAnimationId = record.id
            }
        }
        .onChange(of: expandAnimationId) { _, newId in
            guard newId != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                expandAnimationId = nil
            }
        }
    }
    
    private func syncAnimationContext() {
        animationViewModel.dayKey = viewModel.selectedDayKey
        animationViewModel.loadAnimations()
    }
    
    /// The notebook page grows to fill the right pane. With no animations it
    /// covers the whole viewport; with animations it stays large but leaves a
    /// peek of the gallery so it's discoverable.
    private func pageMinHeight(available: CGFloat) -> CGFloat {
        let usable = max(0, available - 16)
        if animationViewModel.animations.isEmpty {
            return max(440, usable)
        }
        return max(440, usable - 200)
    }

    private var canQuickAnimate: Bool {
        LatexBlockParser.isLikelyMath(selectedText)
            || LatexBlockParser.primary(from: viewModel.editorText, selection: selectedText) != nil
    }
    
    private var quickAnimatePill: some View {
        Button {
            openAnimationStudio()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "function")
                    .font(.caption.weight(.bold))
                Text("Animate Math")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.12, blue: 0.22),
                                Color(red: 0.18, green: 0.14, blue: 0.32)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("Open Math Animation Studio for selected formula")
    }
    
    private func openAnimationStudio() {
        animationViewModel.dayKey = viewModel.selectedDayKey
        animationViewModel.applyNotebookContext(
            text: viewModel.editorText,
            selection: selectedText.isEmpty ? nil : selectedText
        )
        animationViewModel.loadAnimations()
        showAnimationStudio = true
    }
    
    private var notebookHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selectedDayTitle)
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.selectedDaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            NotebookTemplatePicker(selection: viewModel.selectedTemplate) { template in
                Task { await viewModel.setTemplate(template) }
            }
            
            Button {
                openAnimationStudio()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "function")
                        .font(.caption.weight(.semibold))
                    Text("Animate")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule(style: .continuous)
                        .fill(Theme.accent)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Create Manim animation from notebook math")
            
            HStack(spacing: 8) {
                if viewModel.isSaving {
                    ProgressView().controlSize(.mini)
                    Text("Saving")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                if viewModel.entries.contains(where: { $0.dayKey == viewModel.selectedDayKey }) {
                    Button {
                        Task { await viewModel.deleteSelectedPage() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this page")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private var daySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.visibleDayKeys, id: \.self) { dayKey in
                    Button {
                        Task { await viewModel.selectDay(dayKey) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NotebookDayKey.displayTitle(for: dayKey))
                                .font(.caption.weight(viewModel.selectedDayKey == dayKey ? .semibold : .regular))
                            Text(NotebookDayKey.displaySubtitle(for: dayKey))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(
                            viewModel.selectedDayKey == dayKey
                                ? StudyPanelDesign.accent
                                : Color.secondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background {
                            if viewModel.selectedDayKey == dayKey {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(StudyPanelDesign.accent.opacity(0.12))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Page

private struct NotebookPageView: View {
    let template: NotebookPageTemplate
    let plainText: String
    let richContent: Data?
    @Binding var formatting: NotebookPageFormatting
    @Binding var formatCommand: NotebookFormatCommand?
    var onContentChange: (String, Data?) -> Void = { _, _ in }
    var onSelectionChange: (String) -> Void = { _ in }
    
    private var layout: NotebookPageTemplate.Layout { template.layout }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            NotebookTemplateBackground(template: template)
            
            NotebookRichTextEditor(
                plainText: .constant(plainText),
                richContent: .constant(richContent),
                formatting: $formatting,
                formatCommand: $formatCommand,
                lineSpacing: layout.lineSpacing,
                marginInset: layout.marginInset,
                topInset: layout.topInset,
                usesFixedLineHeight: layout.usesFixedLineHeight,
                onContentChange: onContentChange,
                onSelectionChange: onSelectionChange
            )
        }
        .padding(10)
    }
}
