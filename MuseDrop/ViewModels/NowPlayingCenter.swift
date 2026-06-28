//
//  NowPlayingCenter.swift
//  Kekasatori
//
//  Shared registry of open player windows, so the Library can show a "Now Playing"
//  bar that ties the separate player windows back into the app: tap to bring the
//  window forward, or stop it. Player windows keep their own `PlayerViewModel`;
//  this just mirrors the minimum the bar needs (title + playing state) and is
//  populated by `PlayerWindowPresenter` on open/close.
//

import Foundation

@MainActor
final class NowPlayingCenter: ObservableObject {
    static let shared = NowPlayingCenter()

    struct Entry: Identifiable, Equatable {
        let id: UUID
        var title: String
        var isPaper: Bool
        var isPlaying: Bool
    }

    /// Open players, most-recently-opened (or focused) first. `current` drives the
    /// single bar; the rest surface as a "+N" badge.
    @Published private(set) var entries: [Entry] = []

    var current: Entry? { entries.first }

    private init() {}

    /// Register a freshly opened player window. Media starts playing on open; a
    /// research paper is "open" but never plays, so it reads as paused.
    func register(id: UUID, title: String, isPaper: Bool) {
        entries.removeAll { $0.id == id }
        entries.insert(Entry(id: id, title: title, isPaper: isPaper, isPlaying: !isPaper), at: 0)
    }

    func unregister(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Move an entry to the front — called when its window is focused — so the bar
    /// reflects the player the user is actually looking at.
    func bringToFront(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }), idx != 0 else { return }
        let entry = entries.remove(at: idx)
        entries.insert(entry, at: 0)
    }

    func setPlaying(_ playing: Bool, for id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }),
              entries[idx].isPlaying != playing else { return }
        entries[idx].isPlaying = playing
    }
}
