//
//  ExternalDrivesView.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import SwiftUI

struct ExternalDrivesView: View {
    @StateObject private var viewModel = ExternalDrivesViewModel()
    
    var body: some View {
        VStack {
            if viewModel.drives.isEmpty {
                Text("No external drives detected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.drives) { drive in
                    DriveRow(drive: drive, viewModel: viewModel)
                }
            }
            
            HStack {
                Button("Refresh") {
                    viewModel.refreshDrives()
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("External Devices")
    }
}

struct DriveRow: View {
    let drive: ExternalDrive
    @ObservedObject var viewModel: ExternalDrivesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "externaldrive")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(drive.name)
                        .font(.headline)
                    
                    Text(drive.path.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if drive.isDefaultTarget {
                    Text("Default")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
            
            HStack {
                Text("Available: \(formatBytes(drive.availableSpace))")
                    .font(.caption)
                
                Text("Total: \(formatBytes(drive.totalSpace))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Set as Default") {
                    viewModel.setDefaultDrive(drive)
                }
                
                Button("Sync Now") {
                    Task {
                        await viewModel.syncToDrive(drive)
                    }
                }
                .disabled(viewModel.isSyncing)
            }
            
            if viewModel.isSyncing {
                ProgressView(value: viewModel.syncProgress)
                    .padding(.top, 4)
            }
            
            if let error = viewModel.syncError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

