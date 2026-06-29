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
    @Published var selectedSort: SortType = .recent
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

    enum SortType: String, CaseIterable {
        case recent = "Recently added"
        case title = "Title"
        case mastery = "Mastery"
    }
    
    var selectedItem: DownloadItem? {
        guard let selectedItemID else { return nil }
        return filteredItems.first { $0.id == selectedItemID }
    }

    /// An imported playlist collection (header + its items), derived from the
    /// current filtered/sorted set.
    struct PlaylistGroup: Identifiable {
        let id: UUID
        let title: String
        let items: [DownloadItem]
    }

    /// Filtered items that belong to a playlist, grouped by collection (newest
    /// collection first). Item order within a group follows the active sort.
    var playlistGroups: [PlaylistGroup] {
        let withPlaylist = filteredItems.filter { $0.playlistId != nil }
        let grouped = Dictionary(grouping: withPlaylist) { $0.playlistId! }
        return grouped.map { id, items in
            PlaylistGroup(id: id, title: items.first?.playlistTitle ?? "Playlist", items: items)
        }
        .sorted {
            ($0.items.first?.createdDate ?? .distantPast) > ($1.items.first?.createdDate ?? .distantPast)
        }
    }

    /// Filtered items not part of any playlist (rendered as the normal grid).
    var looseItems: [DownloadItem] {
        filteredItems.filter { $0.playlistId == nil }
    }

    // MARK: - Batch study-pack generation (playlist collections)

    /// Live state for a running "generate packs for the whole collection" job.
    /// Slice 1 only transcribes on import; turning every transcript into a full
    /// study pack is this opt-in second step, run one video at a time.
    struct PackBatchProgress {
        let playlistId: UUID
        let total: Int
        var completed = 0   // packs generated this run
        var skipped = 0     // already had a complete pack
        var failed = 0
        var currentTitle = ""
        var processed: Int { completed + skipped + failed }
    }

    @Published var packBatch: PackBatchProgress?
    private var packBatchJob: Task<Void, Never>?
    private var packBatchSession: UUID?

    var isGeneratingPacks: Bool { packBatch != nil }

    /// True while `group` is the collection currently generating packs.
    func isGeneratingPacks(for group: PlaylistGroup) -> Bool {
        packBatch?.playlistId == group.id
    }

    /// Generate a study pack for every video in `group`, sequentially. Items that
    /// already have a complete pack are skipped; per-item failures are isolated so
    /// one bad video can't sink the batch. Each item gets its own coordinator
    /// session so cancellation propagates into the active generation.
    func generatePacks(for group: PlaylistGroup) {
        guard packBatchJob == nil, SettingsViewModel.isAIEnabled else { return }
        let items = group.items
        guard !items.isEmpty else { return }

        packBatch = PackBatchProgress(playlistId: group.id, total: items.count)
        packBatchJob = Task { [weak self] in
            guard let self else { return }
            let ai = MediaAIService.shared
            for item in items {
                if Task.isCancelled { break }
                self.packBatch?.currentTitle = item.displayTitle
                if await ai.isCompleteStudyPack(for: item.id) {
                    self.packBatch?.skipped += 1
                    continue
                }
                let session = UUID()
                self.packBatchSession = session
                await StudyGenerationCoordinator.shared.begin(session: session)
                do {
                    _ = try await ai.generateAnalysis(for: item, session: session)
                    self.packBatch?.completed += 1
                } catch {
                    self.packBatch?.failed += 1
                }
            }
            self.packBatchSession = nil
            let summary = self.packBatch
            self.packBatch = nil
            self.packBatchJob = nil
            self.refreshMastery()
            if let summary, !Task.isCancelled {
                AppStatusCenter.shared.success(
                    "Study packs ready",
                    detail: "\(summary.completed) generated · \(summary.skipped) already done"
                        + (summary.failed > 0 ? " · \(summary.failed) skipped" : "")
                )
            }
        }
    }

    /// Stop the running batch and cancel the in-flight item's generation.
    func cancelPackBatch() {
        packBatchJob?.cancel()
        if let session = packBatchSession {
            Task { await StudyGenerationCoordinator.shared.cancel(session: session) }
        }
        packBatchJob = nil
        packBatchSession = nil
        packBatch = nil
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
            // @Published fires in willSet, so without hopping to the next runloop
            // tick applyFilters() would read the *previous* filter value — that's
            // why the chips appeared to do nothing.
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)

        $selectedSort
            .receive(on: RunLoop.main)
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
        
        filtered = sorted(filtered)
        filteredItems = filtered

        if let selectedItemID,
           !filtered.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = nil
        }
    }

    private func sorted(_ items: [DownloadItem]) -> [DownloadItem] {
        switch selectedSort {
        case .recent:
            return items.sorted { $0.createdDate > $1.createdDate }
        case .title:
            return items.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .mastery:
            // Least-progressed first (what still needs studying), recent as tiebreak.
            func rank(_ item: DownloadItem) -> Int {
                guard let stage = masteryByDownload[item.id],
                      let idx = MasteryStage.allCases.firstIndex(of: stage) else { return -1 }
                return idx
            }
            return items.sorted { a, b in
                let ra = rank(a), rb = rank(b)
                return ra != rb ? ra < rb : a.createdDate > b.createdDate
            }
        }
    }
}
