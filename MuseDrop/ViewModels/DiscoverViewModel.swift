//
//  DiscoverViewModel.swift
//  MuseDrop
//
//  Drives DiscoverView: owns the research question + selected sources, runs
//  DeepResearchAgent on a cancellable Task, and republishes stage updates / the
//  final report on the main actor. Also imports open-access sources into the
//  Library (reusing PaperImportService) so they can be read in-app.
//

import Foundation
import AppKit

/// The two halves of Discover: ask a research question, or browse the trending feed.
enum DiscoverMode: String, CaseIterable, Identifiable {
    case ask
    case trending

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask:      return "Ask"
        case .trending: return "Trending"
        }
    }
}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var mode: DiscoverMode = .ask
    @Published var question: String = ""
    @Published private(set) var isRunning = false
    @Published private(set) var stage: DeepResearchStage?
    @Published private(set) var report: DeepResearchReport?
    @Published private(set) var errorMessage: String?

    /// Which scholarly backends to query (Discover source toggles). All free
    /// metadata APIs; toggling is about discipline coverage + speed, not access.
    @Published var enabledProviders: Set<ScholarlyProviderID> {
        didSet { Self.persist(enabledProviders) }
    }

    /// How hard the research run works (queries/sources + how many papers to read
    /// in full). Persisted across launches.
    @Published var depth: ResearchDepth = ResearchDepth.load() {
        didSet { depth.save() }
    }

    /// `PaperHit.id` of the source currently importing into the Library, if any.
    @Published private(set) var importingPaperID: String?
    @Published var importError: String?
    /// Set when an import finishes; the view opens a reader window and clears it.
    @Published var paperToOpen: DownloadItem?

    /// Which corpus Discover is pointed at (AI vs Medicine).
    @Published private(set) var field: ResearchField = .ai

    // Trending feed (HuggingFace / arXiv / bioRxiv / OpenAlex, by tab + range + domain).
    @Published private(set) var trendingTab: TrendingTab = .trending
    @Published private(set) var trendingRange: TrendingTimeRange = .today
    /// nil = all domains.
    @Published private(set) var trendingDomain: ResearchArea?
    var domains: [ResearchArea] { TaskTaxonomyStore.areas(for: field) }
    @Published private(set) var trending: [PaperHit] = []
    @Published private(set) var trendingLoading = false
    @Published var trendingError: String?

    // Browse: paper-card results for a clicked taxonomy task.
    @Published private(set) var browseQuery: String?
    @Published private(set) var browseResults: [PaperHit] = []
    @Published private(set) var browseLoading = false
    @Published var browseError: String?
    @Published private(set) var browseSort: PaperSort = .relevance
    @Published private(set) var browseRange: TrendingTimeRange = .allTime
    private var browseLimit = 25
    private static let browseLimitCap = 100

    private var task: Task<Void, Never>?
    private var trendingTask: Task<Void, Never>?
    private var browseTask: Task<Void, Never>?

    init() {
        self.enabledProviders = Self.loadProviders(for: .ai)
    }

    // MARK: - Browse (taxonomy task → paper cards)

    var canLoadMoreBrowse: Bool { browseLimit < Self.browseLimitCap }

    /// Browse papers for a task across the enabled providers, shown as cards.
    func browse(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        report = nil
        errorMessage = nil
        browseQuery = trimmed
        browseResults = []
        browseSort = .relevance
        browseRange = .allTime
        browseLimit = 25
        loadBrowse()
    }

    func selectBrowseSort(_ sort: PaperSort) {
        guard sort != browseSort, browseQuery != nil else { return }
        browseSort = sort
        browseLimit = 25
        loadBrowse()
    }

    func selectBrowseRange(_ range: TrendingTimeRange) {
        guard range != browseRange, browseQuery != nil else { return }
        browseRange = range
        browseLimit = 25
        loadBrowse()
    }

    func loadMoreBrowse() {
        guard !browseLoading, canLoadMoreBrowse else { return }
        browseLimit = min(Self.browseLimitCap, browseLimit + 25)
        loadBrowse()
    }

    func exitBrowse() {
        browseTask?.cancel()
        browseTask = nil
        browseQuery = nil
        browseResults = []
        browseError = nil
        browseLoading = false
    }

    /// Clear a finished synthesis, returning to the taxonomy landing.
    func clearReport() {
        report = nil
        errorMessage = nil
    }

    private func loadBrowse() {
        guard let query = browseQuery else { return }
        browseTask?.cancel()
        browseLoading = true
        browseError = nil

        let providers = enabledProviders
        let limit = browseLimit
        let sort = browseSort
        let since = browseRange.since
        browseTask = Task { @MainActor [weak self] in
            let hits = await ScholarlySearchService(enabled: providers)
                .search(query, sort: sort, since: since, limitPerProvider: limit)
            guard !Task.isCancelled else { return }
            self?.browseResults = hits
            self?.browseError = hits.isEmpty ? "No papers found for “\(query)”." : nil
            self?.browseLoading = false
        }
    }

    // MARK: - Field

    /// Switch the active corpus (AI ↔ Medicine): repoint the taxonomy, reset
    /// the trending tab/domain, and clear any in-progress browse/synthesis.
    func selectField(_ newField: ResearchField) {
        guard newField != field else { return }
        field = newField
        enabledProviders = Set(newField.providers)   // field-appropriate sources
        exitBrowse()
        clearReport()
        trendingDomain = nil
        trendingTab = TrendingTab.tabs(for: field).first ?? .newest
        trendingRange = trendingTab.defaultRange
        reloadTrending()
    }

    // MARK: - Trending feed

    /// Load the trending feed the first time it's shown; no-op if already loaded.
    func loadTrendingIfNeeded() {
        guard trending.isEmpty, !trendingLoading else { return }
        reloadTrending()
    }

    func selectTrendingTab(_ tab: TrendingTab) {
        guard tab != trendingTab else { return }
        trendingTab = tab
        if !tab.supportedRanges.contains(trendingRange) {
            trendingRange = tab.defaultRange
        }
        reloadTrending()
    }

    func selectTrendingRange(_ range: TrendingTimeRange) {
        guard range != trendingRange, trendingTab.supportedRanges.contains(range) else { return }
        trendingRange = range
        reloadTrending()
    }

    /// Select a domain filter (nil = all). No-op for the HuggingFace tab.
    func selectTrendingDomain(_ domain: ResearchArea?) {
        guard domain?.id != trendingDomain?.id else { return }
        trendingDomain = domain
        if TrendingFeedService.tabSupportsDomain(trendingTab) {
            reloadTrending()
        }
    }

    func reloadTrending() {
        trendingTask?.cancel()
        trending = []
        trendingLoading = true
        trendingError = nil

        let field = self.field
        let tab = trendingTab
        let range = trendingRange
        let domain = TrendingFeedService.tabSupportsDomain(tab) ? trendingDomain : nil
        trendingTask = Task { @MainActor [weak self] in
            do {
                let hits = try await TrendingFeedService.shared.load(field: field, tab: tab, range: range, domain: domain)
                guard !Task.isCancelled else { return }
                self?.trending = hits
                if hits.isEmpty {
                    self?.trendingError = "No papers found for this view. Try another range."
                }
            } catch is CancellationError {
                return
            } catch {
                self?.trendingError = "Couldn’t load papers: \(error.localizedDescription)"
            }
            self?.trendingLoading = false
        }
    }

    // MARK: - Sources

    func isEnabled(_ id: ScholarlyProviderID) -> Bool { enabledProviders.contains(id) }

    func toggleProvider(_ id: ScholarlyProviderID) {
        if enabledProviders.contains(id) {
            enabledProviders.remove(id)
        } else {
            enabledProviders.insert(id)
        }
    }

    // MARK: - Search & Research

    /// Fast paper lookup from the search box: lists matching papers with no LLM
    /// call and no API key required. Reuses the browse pipeline (same result
    /// cards, sort, range, and pagination). This is the default action; Deep
    /// Research (`run()`) is the explicit, opt-in synthesis.
    func search() {
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !isRunning else { return }
        browse(query)
    }

    func run() {
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 4, !isRunning else { return }
        guard !enabledProviders.isEmpty else {
            errorMessage = "Select at least one source to search."
            return
        }

        task?.cancel()
        exitBrowse()            // a synthesis replaces any list of search results
        report = nil
        errorMessage = nil
        stage = .planning
        isRunning = true

        let agent = DeepResearchAgent(search: ScholarlySearchService(enabled: enabledProviders), depth: depth)
        task = Task { @MainActor [weak self] in
            do {
                let result = try await agent.run(question: query) { [weak self] stage in
                    Task { @MainActor in self?.stage = stage }
                }
                guard !Task.isCancelled else { return }
                self?.finish(with: result)
            } catch is CancellationError {
                self?.finishCancelled()
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(with: error)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        finishCancelled()
    }

    func copyReport() {
        guard let report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.plainText(report), forType: .string)
    }

    /// Copy the cited sources as a BibTeX bibliography.
    func copyBibTeX() {
        guard let report, !report.citations.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BibTeX.bibliography(report.citations), forType: .string)
    }

    // MARK: - Add to Library (open-access only)

    /// Import an open-access source into the Library and open it in the reader.
    /// arXiv preprints import via the rich URL pipeline; bare OA PDFs download
    /// directly. Gated hits never reach here — the view sends those to a browser.
    func addToLibrary(_ hit: PaperHit) {
        guard importingPaperID == nil, hit.isOpenAccess else { return }
        importingPaperID = hit.id
        importError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.paperToOpen = try await Self.importItem(for: hit)
            } catch {
                self.importError = "Couldn’t add “\(hit.title)” to your Library: \(error.localizedDescription)"
            }
            self.importingPaperID = nil
        }
    }

    private static func importItem(for hit: PaperHit) async throws -> DownloadItem {
        if let arxivId = hit.arxivId, !arxivId.isEmpty {
            return try await PaperImportService.shared.importFromURL("https://arxiv.org/abs/\(arxivId)")
        }
        if let pdf = hit.pdfURL, !pdf.isEmpty,
           PaperHit.isReputableScholarlyHost(pdf), let url = URL(string: pdf) {
            return try await PaperImportService.shared.importLocalPDF(from: url)
        }
        throw NSError(
            domain: "Discover", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No open-access full text is available for this paper."]
        )
    }

    // MARK: - Completion (main actor)

    private func finish(with result: DeepResearchReport) {
        report = result
        // Persist the run as a durable brief (workspace context) and remember it.
        let brief = ResearchBriefStore.shared.add(title: result.question, text: Self.plainText(result))
        MemoryCapture.capture(brief)
        stage = .done
        isRunning = false
        task = nil
    }

    private func finishCancelled() {
        isRunning = false
        stage = nil
        task = nil
    }

    private func fail(with error: Error) {
        errorMessage = error.localizedDescription
        isRunning = false
        stage = nil
        task = nil
    }

    // MARK: - Persistence

    // v2: bumped when HuggingFace + GitHub sources were added so existing users'
    // persisted subset (which predates them) is ignored once and everyone gets the
    // full field default — the new sources on by default, still toggleable.
    private static let providersKey = "discover.enabledProviders.v2"

    private static func loadProviders(for field: ResearchField) -> Set<ScholarlyProviderID> {
        let allowed = Set(field.providers)
        guard let raw = UserDefaults.standard.array(forKey: providersKey) as? [String] else { return allowed }
        let set = Set(raw.compactMap(ScholarlyProviderID.init(rawValue:))).intersection(allowed)
        return set.isEmpty ? allowed : set
    }

    private static func persist(_ providers: Set<ScholarlyProviderID>) {
        UserDefaults.standard.set(providers.map(\.rawValue), forKey: providersKey)
    }

    /// Plain-text export: summary followed by a numbered reference list.
    private static func plainText(_ report: DeepResearchReport) -> String {
        var out = report.summary
        guard !report.citations.isEmpty else { return out }
        out += "\n\nSources\n"
        for (index, hit) in report.citations.enumerated() {
            let authors = hit.authors.prefix(3).joined(separator: ", ")
            let meta = [authors, hit.year.map(String.init), hit.venue]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let link = hit.externalURLString ?? ""
            out += "[\(index + 1)] \(hit.title)"
            if !meta.isEmpty { out += " — \(meta)" }
            if !link.isEmpty { out += "\n    \(link)" }
            out += "\n"
        }
        return out
    }
}
