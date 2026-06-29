//
//  PlaylistImportSheet.swift
//  MuseDrop
//
//  Import a whole YouTube playlist as a stream-only collection and transcribe
//  each video. Shows the playlist title + count, an optional cap, then live
//  import/transcribe progress with cancel. Study-pack generation is a separate
//  opt-in step (Library), not done here.
//

import SwiftUI

struct PlaylistImportSheet: View {
    let playlistURL: String
    let kind: StreamMediaKind
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PlaylistImportViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            switch vm.stage {
            case .idle, .loading:
                loadingView
            case .ready:
                readyView
            case .running:
                progressView
            case .finished:
                finishedView
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460, height: 420)
        .onAppear {
            vm.kind = kind
            if vm.stage == .idle { vm.load(playlistURL: playlistURL) }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "list.and.film")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Import playlist").font(.headline)
                if !vm.playlistTitle.isEmpty {
                    Text(vm.playlistTitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Reading the playlist…").font(.callout).foregroundStyle(.secondary)
            if let error = vm.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Found **\(vm.entries.count)** videos.")
                .font(.callout)

            if vm.entries.count > 1 {
                Stepper(value: $vm.limit, in: 1...vm.entries.count) {
                    Text("Import \(vm.totalToImport) of \(vm.entries.count)")
                        .font(.callout)
                }
            }

            if vm.entries.count > 50 {
                Label("Large playlist — consider capping how many to import.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Videos are added as stream-only items and transcribed one by one. Videos without captions are transcribed in full on-device, which is slower.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            row("Imported", value: vm.importedCount, total: vm.totalToImport, systemImage: "tray.and.arrow.down")
            row("Transcribed", value: vm.transcribedCount, total: vm.totalToImport, systemImage: "text.quote")
            if !vm.currentTitle.isEmpty {
                Text(vm.currentTitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if !vm.failures.isEmpty {
                Text("\(vm.failures.count) skipped").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var finishedView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Imported \(vm.importedCount), transcribed \(vm.transcribedCount).",
                  systemImage: "checkmark.seal.fill")
                .foregroundStyle(Theme.success)
            if !vm.failures.isEmpty {
                Text("Skipped \(vm.failures.count):").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(vm.failures) { failure in
                            Text("• \(failure.title)").font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }
            Text("Open Library to generate study packs for the collection.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ label: String, value: Int, total: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(label, systemImage: systemImage).font(.callout)
                Spacer()
                Text("\(value) / \(total)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(value), total: Double(max(total, 1)))
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            switch vm.stage {
            case .ready:
                Button("Cancel") { dismiss() }
                Button("Import") { vm.startImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.entries.isEmpty)
            case .running:
                Button("Cancel", role: .destructive) { vm.cancel() }
            case .finished:
                Button("Done") { onFinished(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .idle, .loading:
                Button("Cancel") { dismiss() }
            }
        }
    }
}
