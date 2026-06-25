//
//  HomeViewModel.swift
//  MuseDrop
//

import Foundation
import SwiftUI
import Combine
import AppKit

enum HomeIngestionMode: String, CaseIterable, Identifiable {
    case download
    case streamOnly
    case research
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .download: return "Download"
        case .streamOnly: return "Stream & Study"
        case .research: return "Research"
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var urlInput: String = ""
    @Published var recentLinks: [String] = []
    @Published var isValidURL: Bool = false
    @Published var isValidPaperInput: Bool = false
    @Published var errorMessage: String?
    @Published var showingDownloadNotification: Bool = false
    @Published var downloadNotificationMessage: String = ""
    @Published var shouldNavigateToDownloads: Bool = false
    @Published var shouldNavigateToLibrary: Bool = false
    @Published var isVideoDownload: Bool = false
    @Published var ingestionMode: HomeIngestionMode = .download
    @Published var isStreamActionInProgress = false
    @Published var streamActionMessage = ""
    @Published var waitElapsedSeconds = 0
    @Published var waitTitle = ""
    @Published var waitDetailMessage = ""
    
    var isHomeOperationInProgress: Bool {
        isStreamActionInProgress || showingDownloadNotification
    }
    
    var consumptionMode: ConsumptionMode {
        ingestionMode == .streamOnly ? .streamOnly : .download
    }
    
    var waitElapsedLabel: String {
        WaitDurationFormatter.format(seconds: waitElapsedSeconds)
    }
    
    var waitSubtitle: String {
        "Please wait · \(waitElapsedLabel)"
    }

    private let downloadEngine = DownloadEngine.shared
    private let streamLibrary = StreamLibraryService.shared
    private let userDefaults = UserDefaults.standard
    private let recentLinksKey = "Kekasatori.recentLinks"
    private var downloadCompletionTask: Task<Void, Never>?
    private var waitTimerTask: Task<Void, Never>?
    
    init() {
        loadRecentLinks()
        validateURL()
    }
    
    func validateURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isValidURL = false
            isValidPaperInput = false
            return
        }
        
        isValidURL = URL(string: trimmed) != nil
        isValidPaperInput = PaperURLDetector.detect(in: trimmed) != nil || trimmed.lowercased().hasSuffix(".pdf")
    }
    
    func importResearchPaper() async {
        let input = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = "Enter an arXiv, PubMed, DOI, or PDF link"
            return
        }
        
        errorMessage = nil
        beginWait(title: "Importing research paper", detail: "Fetching metadata and PDF…")
        
        do {
            let item = try await PaperImportService.shared.importFromURL(input)
            addToRecentLinks(input)
            urlInput = ""
            endWait()
            shouldNavigateToLibrary = true
            _ = item
        } catch {
            errorMessage = error.localizedDescription
            endWait()
        }
    }
    
    func importPDFFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Research PDF"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        Task {
            errorMessage = nil
            beginWait(title: "Importing PDF", detail: "Copying to your library…")
            do {
                _ = try await PaperImportService.shared.importLocalPDF(from: url)
                endWait()
                shouldNavigateToLibrary = true
            } catch {
                errorMessage = error.localizedDescription
                endWait()
            }
        }
    }
    
    func importDroppedPDF(_ url: URL) {
        Task {
            errorMessage = nil
            beginWait(title: "Importing PDF", detail: "Copying to your library…")
            do {
                _ = try await PaperImportService.shared.importLocalPDF(from: url)
                endWait()
                shouldNavigateToLibrary = true
            } catch {
                errorMessage = error.localizedDescription
                endWait()
            }
        }
    }
    
    func download(type: DownloadType) async {
        guard isValidURL else {
            errorMessage = "Please enter a valid URL"
            return
        }

        errorMessage = nil

        let typeString = type == .audio ? "Audio" : "Video"
        isVideoDownload = (type == .video)
        beginWait(
            title: "Downloading \(typeString.lowercased())",
            detail: "Starting download…"
        )
        shouldNavigateToDownloads = true

        do {
            let downloadItem = try await downloadEngine.download(url: urlInput, type: type)
            addToRecentLinks(urlInput)
            urlInput = ""
            monitorDownloadUntilFinished(itemId: downloadItem.id, successNavigatesToLibrary: true)
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
            endWait()
        }
    }
    
    func streamAndStudy(kind: StreamMediaKind) async {
        guard isValidURL else {
            errorMessage = "Please enter a valid URL"
            return
        }
        
        errorMessage = nil
        isStreamActionInProgress = true
        isVideoDownload = kind == .video
        beginWait(
            title: kind == .audio ? "Preparing audio stream" : "Preparing video stream",
            detail: "Fetching video details…"
        )
        
        do {
            waitDetailMessage = "Saving stream bookmark…"
            _ = try await streamLibrary.addStreamItem(url: urlInput, kind: kind)
            addToRecentLinks(urlInput)
            urlInput = ""
            endWait()
            shouldNavigateToLibrary = true
        } catch {
            errorMessage = error.localizedDescription
            endWait()
        }
        
        isStreamActionInProgress = false
    }

    private func monitorDownloadUntilFinished(itemId: UUID, successNavigatesToLibrary: Bool) {
        downloadCompletionTask?.cancel()

        downloadCompletionTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                guard let item = downloadEngine.getDownloadItem(itemId: itemId) else { continue }
                
                await MainActor.run {
                    updateDownloadWaitMessage(for: item)
                }

                switch item.status {
                case .completed:
                    await MainActor.run {
                        endWait()
                        if successNavigatesToLibrary {
                            shouldNavigateToLibrary = true
                        }
                    }
                    return
                case .failed:
                    await MainActor.run {
                        errorMessage = item.errorMessage ?? "Download failed."
                        endWait()
                    }
                    return
                default:
                    continue
                }
            }
        }
    }
    
    private func updateDownloadWaitMessage(for item: DownloadItem) {
        switch item.status {
        case .queued:
            waitDetailMessage = "Queued — starting shortly…"
        case .downloading:
            if item.progress > 0.01 {
                waitDetailMessage = "Downloading… \(Int(item.progress * 100))% complete"
            } else {
                waitDetailMessage = "Downloading — this may take a few minutes"
            }
        case .merging:
            waitDetailMessage = "Merging video and audio…"
        case .converting:
            waitDetailMessage = "Converting to final format…"
        case .completed:
            waitDetailMessage = "Download complete"
        case .failed:
            waitDetailMessage = "Download failed"
        }
    }
    
    private func beginWait(title: String, detail: String) {
        waitElapsedSeconds = 0
        waitTitle = title
        waitDetailMessage = detail
        downloadNotificationMessage = title
        streamActionMessage = title
        showingDownloadNotification = true
        
        waitTimerTask?.cancel()
        waitTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waitElapsedSeconds += 1
            }
        }
    }
    
    private func endWait() {
        waitTimerTask?.cancel()
        waitTimerTask = nil
        waitElapsedSeconds = 0
        waitTitle = ""
        waitDetailMessage = ""
        showingDownloadNotification = false
        downloadNotificationMessage = ""
        streamActionMessage = ""
    }
    
    func goFromURLField() {
        if urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pasteFromClipboard()
        } else {
            validateURL()
        }
    }
    
    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            urlInput = string.trimmingCharacters(in: .whitespacesAndNewlines)
            validateURL()
        }
    }
    
    func clearRecentLinks() {
        recentLinks = []
        userDefaults.removeObject(forKey: recentLinksKey)
    }
    
    private func addToRecentLinks(_ url: String) {
        recentLinks.removeAll { $0 == url }
        recentLinks.insert(url, at: 0)
        
        if recentLinks.count > 10 {
            recentLinks = Array(recentLinks.prefix(10))
        }
        
        saveRecentLinks()
    }
    
    private func loadRecentLinks() {
        recentLinks = userDefaults.stringArray(forKey: recentLinksKey) ?? []
    }
    
    private func saveRecentLinks() {
        userDefaults.set(recentLinks, forKey: recentLinksKey)
    }
}
