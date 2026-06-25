//
//  PaperReaderView.swift
//  MuseDrop
//
//  A focused research-paper reader built on PDFKit. Chrome is owned here:
//  a compact toolbar (page nav, zoom, find, reading theme, read-aloud, info,
//  share), a toggleable Outline / Thumbnails sidebar, in-document search with
//  match navigation, and an Info popover for title/authors/abstract/citation —
//  so paper details never overlap the page and the title isn't repeated.
//

import SwiftUI
import PDFKit
import WebKit
import AVFoundation

// MARK: - Reading theme

enum PaperReadingTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case sepia = "Sepia"
    case night = "Night"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .sepia: return "sun.max"
        case .night: return "moon.stars"
        }
    }
}

enum PaperReaderMode: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case html = "Web"
    var id: String { rawValue }
}

private enum ReaderSidebar: String, Identifiable {
    case outline, thumbnails
    var id: String { rawValue }
}

// MARK: - Controller (owns the PDFView)

@MainActor
final class PaperReaderController: NSObject, ObservableObject {
    struct OutlineItem: Identifiable {
        let id = UUID()
        let label: String
        let level: Int
        let destination: PDFDestination?
    }

    let pdfView = PDFView()

    @Published var pageCount = 0
    @Published var currentPageIndex = 0            // 0-based
    @Published var displayMode: PDFDisplayMode = .singlePageContinuous
    @Published var outline: [OutlineItem] = []
    @Published var hasOutline = false
    @Published var theme: PaperReadingTheme = .system
    @Published var isSpeaking = false
    @Published var zoomPercent = 100
    @Published var matchCount = 0
    @Published var currentMatch = 0                // 1-based for display

    private var matches: [PDFSelection] = []
    private let synthesizer = AVSpeechSynthesizer()
    private var observers: [NSObjectProtocol] = []
    private var isLoaded = false

    override init() {
        super.init()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.wantsLayer = true
        pdfView.pageShadowsEnabled = true
        synthesizer.delegate = self

        observers.append(NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged, object: pdfView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPage() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged, object: pdfView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncZoom() }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        synthesizer.stopSpeaking(at: .immediate)
    }

    func load(url: URL) {
        guard !isLoaded, let document = PDFDocument(url: url) else { return }
        isLoaded = true
        pdfView.document = document
        pageCount = document.pageCount
        buildOutline(document)
        syncPage()
        syncZoom()
    }

    // MARK: Navigation

    var canGoBack: Bool { currentPageIndex > 0 }
    var canGoForward: Bool { currentPageIndex < pageCount - 1 }

    func goToPrevious() { pdfView.goToPreviousPage(nil) }
    func goToNext() { pdfView.goToNextPage(nil) }

    func goTo(pageNumber: Int) {
        guard let document = pdfView.document else { return }
        let index = max(0, min(pageNumber - 1, document.pageCount - 1))
        if let page = document.page(at: index) { pdfView.go(to: page) }
    }

    func go(to destination: PDFDestination?) {
        guard let destination else { return }
        pdfView.go(to: destination)
    }

    private func syncPage() {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return }
        currentPageIndex = document.index(for: page)
    }

    // MARK: Zoom

    func zoomIn() {
        pdfView.autoScales = false
        pdfView.scaleFactor = min(pdfView.maxScaleFactor, pdfView.scaleFactor * 1.15)
        syncZoom()
    }

    func zoomOut() {
        pdfView.autoScales = false
        pdfView.scaleFactor = max(pdfView.minScaleFactor, pdfView.scaleFactor / 1.15)
        syncZoom()
    }

    func zoomToFit() {
        pdfView.autoScales = true
        syncZoom()
    }

    private func syncZoom() {
        zoomPercent = max(1, Int((pdfView.scaleFactor * 100).rounded()))
    }

    // MARK: Display mode

    func setDisplayMode(_ mode: PDFDisplayMode) {
        displayMode = mode
        pdfView.displayMode = mode
    }

    // MARK: Reading theme

    func setTheme(_ theme: PaperReadingTheme) {
        self.theme = theme
        switch theme {
        case .system:
            pdfView.layer?.filters = nil
            pdfView.backgroundColor = .windowBackgroundColor
        case .sepia:
            if let sepia = CIFilter(name: "CISepiaTone", parameters: [kCIInputIntensityKey: 0.45]) {
                pdfView.layer?.filters = [sepia]
            }
            pdfView.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.86, alpha: 1)
        case .night:
            // Invert renders white pages dark and dark text light; the white
            // background inverts to black, giving a true night reading mode.
            if let invert = CIFilter(name: "CIColorInvert") {
                pdfView.layer?.filters = [invert]
            }
            pdfView.backgroundColor = .white
        }
    }

    // MARK: Search

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let document = pdfView.document, trimmed.count >= 2 else {
            clearSearch()
            return
        }
        let found = document.findString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive])
        matches = found
        for selection in found { selection.color = .systemYellow }
        pdfView.highlightedSelections = found.isEmpty ? nil : found
        matchCount = found.count
        currentMatch = found.isEmpty ? 0 : 1
        focusCurrentMatch()
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatch = currentMatch % matches.count + 1
        focusCurrentMatch()
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatch = (currentMatch - 2 + matches.count) % matches.count + 1
        focusCurrentMatch()
    }

    func clearSearch() {
        matches = []
        matchCount = 0
        currentMatch = 0
        pdfView.highlightedSelections = nil
        pdfView.setCurrentSelection(nil, animate: false)
    }

    private func focusCurrentMatch() {
        guard currentMatch > 0, currentMatch <= matches.count else { return }
        let selection = matches[currentMatch - 1]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.scrollSelectionToVisible(nil)
    }

    // MARK: Read aloud

    func toggleReadAloud() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }
        guard let text = pdfView.currentPage?.string, !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    // MARK: Outline

    private func buildOutline(_ document: PDFDocument) {
        var items: [OutlineItem] = []
        if let root = document.outlineRoot {
            flatten(root, level: -1, into: &items)
        }
        outline = items
        hasOutline = !items.isEmpty
    }

    private func flatten(_ node: PDFOutline, level: Int, into items: inout [OutlineItem]) {
        if level >= 0, let label = node.label, !label.isEmpty {
            items.append(OutlineItem(label: label, level: level, destination: node.destination))
        }
        for index in 0..<node.numberOfChildren {
            if let child = node.child(at: index) {
                flatten(child, level: level + 1, into: &items)
            }
        }
    }
}

extension PaperReaderController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - Main view

struct PaperReaderView: View {
    let item: DownloadItem

    @StateObject private var controller = PaperReaderController()
    @State private var metadata: PaperMetadata?
    @State private var mode: PaperReaderMode = .pdf
    @State private var sidebar: ReaderSidebar?
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var showInfo = false
    @State private var pageField = "1"

    private var bundleURL: URL? { item.paperBundleURL }
    private var pdfURL: URL? {
        guard let bundleURL else { return nil }
        let url = bundleURL.appendingPathComponent(PaperMetadata.defaultPDFFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    private var htmlURL: URL? {
        guard let bundleURL, let name = metadata?.htmlFileName else { return nil }
        let url = bundleURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    private var effectiveMode: PaperReaderMode {
        if mode == .html, htmlURL != nil { return .html }
        if pdfURL != nil { return .pdf }
        return htmlURL != nil ? .html : .pdf
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if showSearch, effectiveMode == .pdf { searchBar }
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
        )
        .onAppear(perform: load)
        .onChange(of: controller.currentPageIndex) { _, new in pageField = String(new + 1) }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch effectiveMode {
        case .pdf:
            if pdfURL != nil {
                HStack(spacing: 0) {
                    if let sidebar {
                        sidebarView(sidebar)
                            .frame(width: 200)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        Divider()
                    }
                    PDFViewHost(controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyState("PDF not available for this paper.")
            }
        case .html:
            if let htmlURL {
                PaperHTMLWebView(url: htmlURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState("Web version not available.")
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Sidebar toggles (PDF only)
            if effectiveMode == .pdf {
                HStack(spacing: 2) {
                    if controller.hasOutline {
                        toolbarToggle("list.bullet.indent", help: "Outline", isOn: sidebar == .outline) {
                            toggleSidebar(.outline)
                        }
                    }
                    toolbarToggle("square.grid.2x2", help: "Page thumbnails", isOn: sidebar == .thumbnails) {
                        toggleSidebar(.thumbnails)
                    }
                }

                Divider().frame(height: 16)

                // Page navigation
                HStack(spacing: 4) {
                    toolbarButton("chevron.left", help: "Previous page", disabled: !controller.canGoBack) {
                        controller.goToPrevious()
                    }
                    TextField("", text: $pageField)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .frame(width: 30)
                        .onSubmit { if let n = Int(pageField) { controller.goTo(pageNumber: n) } }
                    Text("/ \(controller.pageCount)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    toolbarButton("chevron.right", help: "Next page", disabled: !controller.canGoForward) {
                        controller.goToNext()
                    }
                }

                Divider().frame(height: 16)

                // Zoom
                HStack(spacing: 4) {
                    toolbarButton("minus.magnifyingglass", help: "Zoom out") { controller.zoomOut() }
                    Button { controller.zoomToFit() } label: {
                        Text("\(controller.zoomPercent)%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44)
                    }
                    .buttonStyle(.plain)
                    .help("Fit to width")
                    toolbarButton("plus.magnifyingglass", help: "Zoom in") { controller.zoomIn() }
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            // Format toggle when both exist
            if pdfURL != nil, htmlURL != nil {
                Picker("", selection: $mode) {
                    ForEach(PaperReaderMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }

            if effectiveMode == .pdf {
                toolbarToggle("magnifyingglass", help: "Find in paper", isOn: showSearch) {
                    withAnimation(Theme.Motion.hover) { showSearch.toggle() }
                    if !showSearch { controller.clearSearch() }
                }

                Menu {
                    Picker("Reading theme", selection: themeBinding) {
                        ForEach(PaperReadingTheme.allCases) {
                            Label($0.rawValue, systemImage: $0.symbol).tag($0)
                        }
                    }
                    Divider()
                    Picker("Layout", selection: displayModeBinding) {
                        Label("Single page", systemImage: "doc").tag(PDFDisplayMode.singlePageContinuous)
                        Label("Two pages", systemImage: "doc.on.doc").tag(PDFDisplayMode.twoUpContinuous)
                    }
                } label: {
                    Image(systemName: controller.theme.symbol)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Reading theme & layout")

                toolbarToggle(controller.isSpeaking ? "stop.circle" : "speaker.wave.2",
                              help: controller.isSpeaking ? "Stop reading" : "Read page aloud",
                              isOn: controller.isSpeaking) {
                    controller.toggleReadAloud()
                }
            }

            toolbarToggle("info.circle", help: "Paper details", isOn: showInfo) {
                showInfo.toggle()
            }
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                infoPopover
            }

            moreMenu
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.regularMaterial)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in paper…", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { controller.search(searchText) }
                .onChange(of: searchText) { _, value in
                    if value.isEmpty { controller.clearSearch() }
                }
            if controller.matchCount > 0 {
                Text("\(controller.currentMatch) of \(controller.matchCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if !searchText.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            toolbarButton("chevron.up", help: "Previous match", disabled: controller.matchCount == 0) {
                controller.previousMatch()
            }
            toolbarButton("chevron.down", help: "Next match", disabled: controller.matchCount == 0) {
                controller.nextMatch()
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.regularMaterial)
    }

    private var moreMenu: some View {
        Menu {
            if let url = pdfURL {
                Button("Open in Default App", systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(url)
                }
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                ShareLink(item: url) { Label("Share PDF", systemImage: "square.and.arrow.up") }
            }
            if let source = URL(string: item.url) {
                Divider()
                Link(destination: source) { Label("Open Source Page", systemImage: "safari") }
            }
            if let citation = citationText {
                Divider()
                Button("Copy Citation", systemImage: "quote.opening") {
                    copyToPasteboard(citation)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More")
    }

    // MARK: Sidebar

    @ViewBuilder
    private func sidebarView(_ kind: ReaderSidebar) -> some View {
        switch kind {
        case .outline:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(controller.outline) { item in
                        Button {
                            controller.go(to: item.destination)
                        } label: {
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(item.level == 0 ? .primary : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(item.level) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Theme.Spacing.sm)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        case .thumbnails:
            PDFThumbnailHost(controller: controller)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: Info popover

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                StatusPill(text: metadata?.source.displayName ?? item.displayFormat,
                           systemImage: "doc.text", color: Theme.accent)
                if let published = metadata?.publishedAt, !published.isEmpty {
                    Text(published)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(metadata?.title ?? item.displayTitle)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if let authors = metadata?.authors, !authors.isEmpty {
                Text(authors.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let abstract = metadata?.abstract, !abstract.isEmpty {
                Divider()
                ScrollView {
                    Text(abstract)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }

            if let citation = citationText {
                Divider()
                Button {
                    copyToPasteboard(citation)
                } label: {
                    Label("Copy Citation", systemImage: "quote.opening")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360)
    }

    // MARK: Helpers

    private func emptyState(_ message: String) -> some View {
        EmptyStateView(systemImage: "doc.questionmark", title: "Unavailable", message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    private func toolbarButton(_ symbol: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .disabled(disabled)
        .help(help)
    }

    private func toolbarToggle(_ symbol: String, help: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
        .help(help)
    }

    private var themeBinding: Binding<PaperReadingTheme> {
        Binding(get: { controller.theme }, set: { controller.setTheme($0) })
    }

    private var displayModeBinding: Binding<PDFDisplayMode> {
        Binding(get: { controller.displayMode }, set: { controller.setDisplayMode($0) })
    }

    private func toggleSidebar(_ kind: ReaderSidebar) {
        withAnimation(Theme.Motion.spring) {
            sidebar = (sidebar == kind) ? nil : kind
        }
    }

    private var citationText: String? {
        guard let metadata else { return nil }
        var parts: [String] = []
        if !metadata.authors.isEmpty { parts.append(metadata.authors.joined(separator: ", ") + ".") }
        if let year = metadata.publishedAt, !year.isEmpty { parts.append("(\(year)).") }
        parts.append(metadata.title + ".")
        parts.append(metadata.source.displayName + ".")
        if let doi = metadata.doi, !doi.isEmpty {
            parts.append("https://doi.org/\(doi)")
        } else if !metadata.sourceURL.isEmpty {
            parts.append(metadata.sourceURL)
        }
        let text = parts.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func load() {
        if let bundleURL { metadata = PaperMetadataStore.load(bundleURL: bundleURL) }
        if pdfURL == nil, htmlURL != nil { mode = .html }
        if let pdfURL { controller.load(url: pdfURL) }
    }
}

// MARK: - PDFKit hosts

private struct PDFViewHost: NSViewRepresentable {
    @ObservedObject var controller: PaperReaderController

    func makeNSView(context: Context) -> PDFView { controller.pdfView }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

private struct PDFThumbnailHost: NSViewRepresentable {
    @ObservedObject var controller: PaperReaderController

    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = controller.pdfView
        view.thumbnailSize = NSSize(width: 150, height: 200)
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {
        if nsView.pdfView !== controller.pdfView {
            nsView.pdfView = controller.pdfView
        }
    }
}

private struct PaperHTMLWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }
}
