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
    @Published var sortOrder: SortOrder = .recentlyStudied

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

    enum SortOrder: String, CaseIterable {
        case recentlyStudied = "Recently studied"
        case dateCreated = "Date created"
        case title = "Title A–Z"
        case mastery = "Mastery"
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

        $sortOrder
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

        filteredPacks = sorted(filtered)
    }

    /// Pinned packs always float to the top; the rest follow `sortOrder`.
    private func sorted(_ packs: [StudyPackSummary]) -> [StudyPackSummary] {
        packs.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            switch sortOrder {
            case .recentlyStudied:
                return (a.lastStudiedAt ?? a.updatedAt) > (b.lastStudiedAt ?? b.updatedAt)
            case .dateCreated:
                return a.createdAt > b.createdAt
            case .title:
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            case .mastery:
                // Least-mastered first — surfaces what still needs work.
                let ra = a.masteryStage?.rank ?? 0
                let rb = b.masteryStage?.rank ?? 0
                if ra != rb { return ra < rb }
                return (a.lastStudiedAt ?? a.updatedAt) > (b.lastStudiedAt ?? b.updatedAt)
            }
        }
    }

    // MARK: - Organization actions

    // These persist a single field then patch the in-memory array and re-filter
    // — no full refetch, so the board/list updates instantly on drop.

    func setMastery(_ stage: MasteryStage?, for pack: StudyPackSummary) {
        dataStore.setMasteryStage(stage, forSession: pack.sessionId)
        update(pack.sessionId) { $0.masteryStageRaw = stage?.rawValue }
    }

    func togglePin(for pack: StudyPackSummary) {
        let pinned = !pack.isPinned
        dataStore.setPinned(pinned, forSession: pack.sessionId)
        update(pack.sessionId) { $0.isPinned = pinned }
    }

    func markStudied(for pack: StudyPackSummary) {
        dataStore.markStudied(sessionId: pack.sessionId)
        update(pack.sessionId) { $0.lastStudiedAt = Date() }
    }

    private func update(_ sessionId: UUID, _ mutate: (inout StudyPackSummary) -> Void) {
        guard let index = packs.firstIndex(where: { $0.sessionId == sessionId }) else { return }
        mutate(&packs[index])
        applyFilters()
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
