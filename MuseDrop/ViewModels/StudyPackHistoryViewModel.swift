//
//  StudyPackHistoryViewModel.swift
//  MuseDrop
//

import Foundation
import Combine

@MainActor
final class StudyPackHistoryViewModel: ObservableObject {
    @Published var packs: [StudyPackSummary] = []
    @Published var filteredPacks: [StudyPackSummary] = []
    @Published var searchText = ""
    @Published var selectedFilter: Filter = .all
    
    private let dataStore = DataStore.shared
    private let libraryManager = LibraryManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    enum Filter: String, CaseIterable {
        case all = "All"
        case downloaded = "Downloaded"
        case streamed = "Streamed"
        case papers = "Papers"
        case audio = "Audio"
        case video = "Video"
    }
    
    init() {
        setupObservers()
        reload()
    }
    
    private func setupObservers() {
        libraryManager.$downloads
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
        
        $searchText
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
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
    
    func reload() {
        packs = dataStore.fetchAllStudyPackSummaries()
        applyFilters()
    }
    
    /// Full generated study pack content, for export/share. Nil if not loadable.
    func analysis(for pack: StudyPackSummary) -> MediaAnalysis? {
        dataStore.loadAnalysis(for: pack.downloadId)
    }

    func downloadItem(for pack: StudyPackSummary) -> DownloadItem? {
        if let item = libraryManager.getDownload(by: pack.downloadId) {
            return item
        }
        guard let record = dataStore.fetchDownload(id: pack.downloadId) else { return nil }
        return MediaAnalysisMapper.toDownloadItem(record)
    }
    
    private func applyFilters() {
        var filtered = packs
        
        switch selectedFilter {
        case .all:
            break
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
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { pack in
                pack.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || pack.summaryOneLine.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        filteredPacks = filtered
    }
    
    func artifactLabel(for kindRaw: String?) -> String {
        guard let kindRaw else { return "Generated" }
        switch kindRaw {
        case AIStudyArtifactKind.fullPack.rawValue: return "Full pack"
        case AIStudyArtifactKind.regenerated.rawValue: return "Regenerated"
        case AIStudyArtifactKind.transcript.rawValue: return "Transcript"
        case AIStudyArtifactKind.summary.rawValue: return "Summary"
        case AIStudyArtifactKind.notes.rawValue: return "Notes"
        case AIStudyArtifactKind.flashcards.rawValue: return "Cards"
        case AIStudyArtifactKind.mindMap.rawValue: return "Mind map"
        case AIStudyArtifactKind.concepts.rawValue: return "Concepts"
        default: return kindRaw.capitalized
        }
    }
}
