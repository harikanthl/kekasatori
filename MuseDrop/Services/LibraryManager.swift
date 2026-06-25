//
//  LibraryManager.swift
//  MuseDrop
//

import Foundation
import Combine

@MainActor
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    
    @Published var downloads: [DownloadItem] = []
    private let logService = LogService.shared
    private let dataStore = DataStore.shared
    
    private init() {
        reloadDownloads()
    }
    
    func reloadDownloads() {
        let all = dataStore.fetchAllDownloads()
        
        downloads = all.filter { item in
            switch item.status {
            case .completed:
                if item.isStreamOnly {
                    return true
                }
                guard let outputPath = item.outputPath else { return false }
                let exists = FileManager.default.fileExists(atPath: outputPath.path)
                if !exists {
                    logService.warning("Missing file for download: \(item.title)")
                    dataStore.removeDownload(id: item.id)
                }
                return exists
            case .failed, .queued, .downloading, .merging, .converting:
                return true
            }
        }
        
        logService.info("Loaded \(downloads.count) downloads from SwiftData")
    }
    
    func saveDownloads() {
        // Downloads are persisted per upsert; this reloads the in-memory view.
        reloadDownloads()
    }
    
    func addDownload(_ item: DownloadItem) {
        dataStore.upsertDownload(item)
        reloadDownloads()
    }
    
    func updateDownload(_ item: DownloadItem) {
        dataStore.upsertDownload(item)
        if let index = downloads.firstIndex(where: { $0.id == item.id }) {
            let refreshed = dataStore.fetchAllDownloads().first { $0.id == item.id } ?? item
            downloads[index] = refreshed
        } else {
            reloadDownloads()
        }
    }
    
    func removeDownload(_ item: DownloadItem) {
        dataStore.removeDownload(id: item.id)
        downloads.removeAll { $0.id == item.id }
    }
    
    /// Removes media files, canvas data, study packs, and the SwiftData record.
    func deleteCompletely(_ item: DownloadItem) async {
        PlayerWindowPresenter.close(for: item.id)
        
        let boards = await dataStore.canvasPersistence.boards(for: item.id)
        for board in boards {
            try? FileManager.default.removeItem(at: PathUtils.canvasBoardDirectory(board.id))
        }
        
        if let path = item.outputPath {
            try? FileUtils.deleteFile(at: path)
        }
        
        if item.isResearchDocument {
            try? FileManager.default.removeItem(at: PathUtils.paperBundleDirectory(itemId: item.id))
        }
        
        if let thumbnail = item.thumbnail {
            try? FileUtils.deleteFile(at: thumbnail)
        }
        
        let legacyAnalysis = PathUtils.analysisDirectory
            .appendingPathComponent("\(item.id.uuidString).json")
        try? FileUtils.deleteFile(at: legacyAnalysis)
        
        await RAGIndexService.shared.remove(downloadId: item.id)

        dataStore.removeDownload(id: item.id)
        downloads.removeAll { $0.id == item.id }
        logService.info("Deleted library item and all associated data: \(item.displayTitle)")
    }
    
    func getDownload(by id: UUID) -> DownloadItem? {
        downloads.first { $0.id == id }
    }
    
    func markSummaryExists(for id: UUID) {
        dataStore.markStudyAvailable(for: id)
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            var item = downloads[index]
            item.summaryExists = true
            downloads[index] = item
        }
    }
    
    func getDownloads(by status: DownloadStatus) -> [DownloadItem] {
        downloads.filter { $0.status == status }
    }
}
