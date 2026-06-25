//
//  NotebookViewModel.swift
//  MuseDrop
//

import Foundation
import Combine

@MainActor
final class NotebookViewModel: ObservableObject {
    @Published var entries: [UserNotebookEntry] = []
    @Published var selectedDayKey: String
    @Published var editorText: String = ""
    @Published var richContent: Data?
    @Published var pageFormatting: NotebookPageFormatting = .default
    @Published var selectedTemplate: NotebookPageTemplate = .ruled
    @Published var formatCommand: NotebookFormatCommand?
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var statusMessage: String?
    
    let downloadId: UUID
    let mediaTitle: String
    
    private var saveTask: Task<Void, Never>?
    private var saveGeneration: UInt = 0
    private var loadGeneration: UInt = 0
    
    init(downloadId: UUID, mediaTitle: String) {
        self.downloadId = downloadId
        self.mediaTitle = mediaTitle
        self.selectedDayKey = NotebookDayKey.today()
    }
    
    var selectedDayTitle: String {
        NotebookDayKey.displayTitle(for: selectedDayKey)
    }
    
    var selectedDaySubtitle: String {
        NotebookDayKey.displaySubtitle(for: selectedDayKey)
    }
    
    var visibleDayKeys: [String] {
        var keys = Set(entries.map(\.dayKey))
        keys.insert(NotebookDayKey.today())
        keys.insert(selectedDayKey)
        return keys.sorted(by: >)
    }
    
    func loadEntries() async {
        let generation = loadGeneration &+ 1
        loadGeneration = generation
        isLoading = true
        
        let list = await persistence().entries(for: downloadId)
        guard generation == loadGeneration else { return }
        
        entries = list
        applyEntryContent(for: selectedDayKey)
        isLoading = false
    }
    
    func selectDay(_ dayKey: String) async {
        guard dayKey != selectedDayKey else { return }
        await flushSave()
        selectedDayKey = dayKey
        applyEntryContent(for: dayKey)
    }
    
    func updateText(_ text: String) {
        editorText = text
        scheduleSave()
    }
    
    func updateRichContent(_ data: Data?) {
        richContent = data
    }
    
    func updateEditorContent(text: String, richContent data: Data?) {
        editorText = text
        richContent = data
        scheduleSave()
    }
    
    func updateFormatting(_ formatting: NotebookPageFormatting) {
        pageFormatting = formatting
        scheduleSave()
    }
    
    func sendFormatCommand(_ command: NotebookFormatCommand) {
        formatCommand = command
    }
    
    func setTemplate(_ template: NotebookPageTemplate) async {
        guard template != selectedTemplate else { return }
        saveTask?.cancel()
        saveGeneration &+= 1
        selectedTemplate = template
        
        if let saved = await saveCurrentEntry() {
            upsertLocalEntry(saved)
        } else {
            entries.removeAll { $0.dayKey == selectedDayKey }
        }
        
        isSaving = false
        statusMessage = "Template updated"
    }
    
    func flushSave() async {
        saveTask?.cancel()
        saveGeneration &+= 1
        
        if let saved = await saveCurrentEntry() {
            upsertLocalEntry(saved)
        } else {
            entries.removeAll { $0.dayKey == selectedDayKey }
        }
        
        isSaving = false
        statusMessage = nil
    }
    
    func deleteSelectedPage() async {
        guard let entry = entries.first(where: { $0.dayKey == selectedDayKey }) else {
            resetEditorState()
            return
        }
        
        saveTask?.cancel()
        saveGeneration &+= 1
        await persistence().deleteEntry(id: entry.id)
        entries.removeAll { $0.id == entry.id }
        resetEditorState()
        statusMessage = "Page deleted"
    }
    
    // MARK: - Private
    
    private func persistence() async -> NotebookPersistenceActor {
        await MainActor.run { DataStore.shared.notebookPersistence }
    }
    
    private func applyEntryContent(for dayKey: String) {
        if let entry = entries.first(where: { $0.dayKey == dayKey }) {
            editorText = entry.content
            richContent = entry.richContent
            pageFormatting = entry.formatting
            selectedTemplate = entry.template
        } else {
            resetEditorState()
        }
    }
    
    private func resetEditorState() {
        editorText = ""
        richContent = nil
        pageFormatting = .default
        selectedTemplate = .ruled
    }
    
    private func saveCurrentEntry() async -> UserNotebookEntry? {
        await persistence().saveEntry(
            downloadId: downloadId,
            dayKey: selectedDayKey,
            content: editorText,
            richContent: richContent,
            formattingJSON: pageFormatting.encodedJSON(),
            templateRaw: selectedTemplate.rawValue
        )
    }
    
    private func scheduleSave() {
        let generation = saveGeneration &+ 1
        saveGeneration = generation
        
        saveTask?.cancel()
        isSaving = true
        statusMessage = nil
        
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, generation == saveGeneration else { return }
            
            if let saved = await saveCurrentEntry() {
                guard generation == saveGeneration else { return }
                upsertLocalEntry(saved)
                isSaving = false
                statusMessage = "Saved"
            } else {
                guard generation == saveGeneration else { return }
                entries.removeAll { $0.dayKey == selectedDayKey }
                isSaving = false
                statusMessage = nil
            }
        }
    }
    
    private func upsertLocalEntry(_ entry: UserNotebookEntry) {
        if let index = entries.firstIndex(where: { $0.dayKey == entry.dayKey }) {
            entries[index] = entry
        } else {
            entries.append(entry)
            entries.sort { $0.dayKey > $1.dayKey }
        }
    }
}
