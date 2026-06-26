//
//  LibraryViewModel.swift
//  MuseDrop
//

import Foundation
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var mediaItems: [DownloadItem] = []
    @Published var filteredItems: [DownloadItem] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: FilterType = .all
    @Published var selectedItemID: UUID?
    @Published var isDeleting = false
    /// Source download id → mastery stage, for the mastery badge on cards.
    @Published var masteryByDownload: [UUID: MasteryStage] = [:]

    private let libraryManager = LibraryManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    enum FilterType: String, CaseIterable {
        case all = "All"
        case downloaded = "Downloaded"
        case streamed = "Streamed"
        case papers = "Papers"
        case audio = "Audio"
        case video = "Video"
    }
    
    var selectedItem: DownloadItem? {
        guard let selectedItemID else { return nil }
        return filteredItems.first { $0.id == selectedItemID }
    }
    
    init() {
        setupObservers()
        loadMedia()
    }
    
    private func setupObservers() {
        libraryManager.$downloads
            .sink { [weak self] downloads in
                self?.mediaItems = downloads.filter(Self.isLibraryItem)
                self?.refreshMastery()
                self?.applyFilters()
            }
            .store(in: &cancellables)
        
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
        
        $selectedFilter
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }
    
    private static func isLibraryItem(_ item: DownloadItem) -> Bool {
        guard item.status == .completed else { return false }
        if item.isStreamOnly { return true }
        return item.outputPath != nil
    }
    
    private func loadMedia() {
        mediaItems = libraryManager.downloads.filter(Self.isLibraryItem)
        refreshMastery()
        applyFilters()
    }

    /// Refresh the download → mastery map (call when the view appears, since
    /// mastery can be changed from the Study Packs tab while Library is open).
    func refreshMastery() {
        masteryByDownload = DataStore.shared.masteryStagesByDownload()
    }
    
    func select(_ item: DownloadItem) {
        selectedItemID = item.id
    }
    
    func deleteSelectedItem() async {
        guard let item = selectedItem else { return }
        isDeleting = true
        defer { isDeleting = false }
        await libraryManager.deleteCompletely(item)
        if selectedItemID == item.id {
            selectedItemID = nil
        }
    }
    
    func delete(_ item: DownloadItem) async {
        isDeleting = true
        defer { isDeleting = false }
        await libraryManager.deleteCompletely(item)
        if selectedItemID == item.id {
            selectedItemID = nil
        }
    }
    
    private func applyFilters() {
        var filtered = mediaItems
        
        switch selectedFilter {
        case .downloaded:
            filtered = filtered.filter { !$0.isStreamOnly }
        case .streamed:
            filtered = filtered.filter(\.isStreamOnly)
        case .papers:
            filtered = filtered.filter(\.isResearchDocument)
        case .audio:
            filtered = filtered.filter { $0.isAudioMedia && !$0.isResearchDocument }
        case .video:
            filtered = filtered.filter { !$0.isAudioMedia && !$0.isResearchDocument && !$0.isStreamOnly }
        case .all:
            break
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || item.url.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        filteredItems = filtered
        
        if let selectedItemID,
           !filtered.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }
}
