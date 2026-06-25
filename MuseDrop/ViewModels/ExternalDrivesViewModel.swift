//
//  ExternalDrivesViewModel.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation
import Combine

@MainActor
class ExternalDrivesViewModel: ObservableObject {
    @Published var drives: [ExternalDrive] = []
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
    @Published var syncError: String?
    
    private let driveManager = ExternalDriveManager.shared
    private let libraryManager = LibraryManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupObservers()
        refreshDrives()
    }
    
    private func setupObservers() {
        driveManager.$drives
            .assign(to: &$drives)
    }
    
    func refreshDrives() {
        driveManager.detectDrives()
    }
    
    func setDefaultDrive(_ drive: ExternalDrive) {
        driveManager.setDefaultDrive(drive)
    }
    
    func syncToDrive(_ drive: ExternalDrive) async {
        isSyncing = true
        syncError = nil
        syncProgress = 0.0
        
        let files = await libraryManager.downloads
            .filter { $0.status == .completed }
            .compactMap { $0.outputPath }
        
        do {
            try await driveManager.syncFiles(to: drive, files: files) { [weak self] progress in
                Task { @MainActor in
                    self?.syncProgress = progress
                }
            }
        } catch {
            syncError = error.localizedDescription
        }
        
        isSyncing = false
    }
}

