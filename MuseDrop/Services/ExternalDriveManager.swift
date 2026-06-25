//
//  ExternalDriveManager.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation
import Combine

@MainActor
class ExternalDriveManager: ObservableObject {
    static let shared = ExternalDriveManager()
    
    @Published var drives: [ExternalDrive] = []
    private let logService = LogService.shared
    
    private init() {
        detectDrives()
    }
    
    func detectDrives() {
        drives.removeAll()
        
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        
        for volumeURL in mountedVolumes {
            do {
                // Request resource values - keys have "Key" suffix
                let resourceValues = try volumeURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeIsRemovableKey,
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey
                ])
                
                // Access properties - properties do NOT have "Key" suffix
                // Check if volume is removable (external drive)
                guard let isRemovable = resourceValues.volumeIsRemovable, isRemovable else {
                    continue
                }
                
                // Get volume properties (these are optional, so provide defaults)
                let name = resourceValues.volumeName ?? "Untitled"
                // volumeTotalCapacity and volumeAvailableCapacity return Int? (convert to Int64)
                let totalSpace = Int64(resourceValues.volumeTotalCapacity ?? 0)
                let availableSpace = Int64(resourceValues.volumeAvailableCapacity ?? 0)
                
                let drive = ExternalDrive(
                    name: name,
                    path: volumeURL,
                    availableSpace: availableSpace,
                    totalSpace: totalSpace,
                    isDefaultTarget: false
                )
                
                drives.append(drive)
            } catch {
                logService.error("Failed to get drive info for \(volumeURL.path)", error: error)
            }
        }
        
        logService.info("Detected \(drives.count) external drives")
    }
    
    func setDefaultDrive(_ drive: ExternalDrive) {
        for index in drives.indices {
            drives[index].isDefaultTarget = (drives[index].id == drive.id)
        }
    }
    
    func getDefaultDrive() -> ExternalDrive? {
        drives.first { $0.isDefaultTarget }
    }
    
    func syncFiles(to drive: ExternalDrive, files: [URL], progress: @escaping @Sendable (Double) -> Void) async throws {
        let destinationDir = drive.path.appendingPathComponent("Kekasatori")
        try FileUtils.createDirectory(at: destinationDir)

        var copied = 0
        for file in files {
            try Task.checkCancellation()
            let filename = file.lastPathComponent
            let destination = destinationDir.appendingPathComponent(filename)
            
            // Skip if file already exists
            if FileUtils.fileExists(at: destination) {
                logService.info("Skipping \(filename) - already exists")
                copied += 1
                progress(Double(copied) / Double(files.count))
                continue
            }
            
            try FileUtils.copyFile(from: file, to: destination)
            copied += 1
            progress(Double(copied) / Double(files.count))
        }
        
        logService.info("Synced \(copied) files to \(drive.name)")
    }
}

