//
//  AppUpdater.swift
//  MuseDrop (Kekasatori)
//
//  Sparkle-based auto-update for direct (non–App Store) distribution.
//  Feed URL and public EdDSA key are read from Info.plist build settings
//  (SUFeedURL / SUPublicEDKey). Updates are EdDSA-signed; see Scripts/.
//

import SwiftUI
import Combine
import Sparkle

/// Owns the Sparkle updater and exposes a SwiftUI-friendly "can check" flag.
@MainActor
final class AppUpdater: ObservableObject {
    @Published var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        // Don't start background checks until a real EdDSA public key is set
        // (the project ships a placeholder). Once configured, scheduled checks
        // begin automatically. The "Check for Updates…" menu still works.
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let keyConfigured = (publicKey?.isEmpty == false)
            && publicKey != "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

        controller = SPUStandardUpdaterController(
            startingUpdater: keyConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Trigger a user-initiated update check (shows Sparkle's standard UI).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

/// Menu command — adds "Check for Updates…" under the app menu.
struct CheckForUpdatesCommand: Commands {
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
