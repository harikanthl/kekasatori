//
//  YouTubeSearchSheet.swift
//  Kekasatori
//
//  Search YouTube from inside the app (no API key) and pick a video to load.
//

import SwiftUI

struct YouTubeSearchSheet: View {
    let onSelect: (YouTubeSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [YouTubeSearchResult] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var hasSearched = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Theme.Spacing.md)
        }
        .frame(width: 580, height: 540)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search YouTube…", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit(runSearch)
            if isSearching {
                ProgressView().controlSize(.small)
            }
            Button("Search", action: runSearch)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
        .padding(Theme.Spacing.md)
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            centered {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Search failed", message: error)
            }
        } else if !hasSearched {
            centered {
                EmptyStateView(systemImage: "magnifyingglass", title: "Search YouTube",
                               message: "Find a video by name — no link needed.")
            }
        } else if results.isEmpty && !isSearching {
            centered {
                EmptyStateView(systemImage: "magnifyingglass", title: "No results", message: "Try a different search.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            resultRow(result)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private func centered<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultRow(_ r: YouTubeSearchResult) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            AsyncImage(url: r.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 120, height: 68)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if let d = r.durationLabel {
                    Text(d)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(r.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !r.channel.isEmpty {
                    Text(r.channel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        error = nil
        hasSearched = true
        Task {
            do {
                let found = try await YouTubeSearchService.shared.search(q)
                await MainActor.run {
                    results = found
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }
}
