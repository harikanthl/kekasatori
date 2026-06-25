//
//  DownloadsViewModel.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation
import Combine

@MainActor
class DownloadsViewModel: ObservableObject {
    @Published var activeDownloads: [DownloadItem] = []
    @Published var completedDownloads: [DownloadItem] = []
    @Published var failedDownloads: [DownloadItem] = []
    @Published var errorMessage: String?
    
    private let downloadEngine: DownloadEngine
    private let libraryManager: LibraryManager

    private var cancellables = Set<AnyCancellable>()

    private static let activeStatuses: Set<DownloadStatus> = [
        .queued, .downloading, .merging, .converting
    ]

    init() {
        downloadEngine = DownloadEngine.shared
        libraryManager = LibraryManager.shared
        setupObservers()
        refreshLists()
    }
    
    private func setupObservers() {
        downloadEngine.$activeDownloads
            .sink { [weak self] _ in
                self?.refreshLists()
            }
            .store(in: &cancellables)
        
        libraryManager.$downloads
            .sink { [weak self] _ in
                self?.refreshLists()
            }
            .store(in: &cancellables)
    }
    
    /// Merge persisted downloads with in-memory engine state so status labels stay accurate.
    private func refreshLists() {
        var merged = Dictionary(uniqueKeysWithValues: libraryManager.downloads.map { ($0.id, $0) })
        
        for item in downloadEngine.activeDownloads.values {
            merged[item.id] = item
        }
        
        let sorted = merged.values.sorted { $0.createdDate > $1.createdDate }
        
        activeDownloads = sorted.filter { Self.activeStatuses.contains($0.status) }
        completedDownloads = sorted.filter { $0.status == .completed }
        failedDownloads = sorted.filter { $0.status == .failed }
    }
    
    func cancelDownload(_ item: DownloadItem) {
        downloadEngine.cancelDownload(item)
    }
    
    func retryDownload(_ item: DownloadItem) async {
        let type: DownloadType = item.format.contains("audio") || item.format.contains("mp3") ? .audio : .video
        do {
            _ = try await downloadEngine.download(url: item.url, type: type)
        } catch {
            LogService.shared.error("Retry download failed", error: error)
            errorMessage = "Couldn't retry “\(item.displayTitle)”: \(error.localizedDescription)"
        }
    }
}
