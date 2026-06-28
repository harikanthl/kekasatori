//
//  CodeBoxView.swift
//  MuseDrop
//
//  The Code box: write code on the left, run it in a container and watch output
//  stream on the right. CPU-only locally (no Mac GPU passthrough); a remote-GPU
//  push comes later. The native editor is a v1 — Monaco swaps in via the
//  Excalidraw WebView pattern.
//

import SwiftUI

struct CodeBoxView: View {
    @StateObject private var model = CodeBoxViewModel()
    @Environment(\.colorScheme) private var colorScheme

    static let imagePresets: [(label: String, image: String)] = [
        ("Python (slim)", "python:3.12-slim"),
        ("PyTorch (CPU)", "pytorch/pytorch:2.5.1-cpu"),
        ("PyTorch + CUDA", "pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime"),
        ("Python 3.12", "python:3.12"),
        ("Ubuntu 24.04", "ubuntu:24.04")
    ]

    private var monacoLanguage: String {
        switch model.spec.language {
        case .python: return "python"
        case .bash:   return "shell"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    ScreenHeader(
                        title: "Code",
                        subtitle: "Write and run code in a container — prototype locally, scale to a GPU.",
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                    runButton
                }
                SectionRule()
                controls
                if let runtime = model.runtime, !runtime.isReady {
                    runtimeBanner(runtime)
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.md)

            HStack(spacing: 0) {
                editor
                SectionRule(axis: .vertical)
                console
            }
        }
        .onChange(of: model.spec.language) { _, _ in model.loadStarterIfEmpty() }
    }

    // MARK: - Header controls

    @ViewBuilder
    private var runButton: some View {
        if model.isRunning {
            Button(role: .cancel) { model.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .controlSize(.large)
        } else {
            Button { model.run() } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canRun)
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            Picker("Language", selection: $model.spec.language) {
                ForEach(CodeRunSpec.Language.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                TextField(model.spec.language.defaultImage, text: $model.spec.image)
                    .textFieldStyle(.plain)
                    .font(.callout.monospaced())
                Menu {
                    ForEach(Self.imagePresets, id: \.image) { preset in
                        Button(preset.label) { model.spec.image = preset.image }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .floatingChrome(radius: Theme.Radius.md)

            if let runtime = model.runtime, let engine = runtime.engine {
                StatusPill(text: engine.displayName, systemImage: "cube.box", color: Theme.success)
                if model.canStartEngine {
                    Button("Start engine") { model.startEngine() }
                        .controlSize(.small)
                        .help("Run `container system start`")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func runtimeBanner(_ runtime: ContainerRuntimeStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text(runtime.statusMessage)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if model.canInstallAppleContainer {
                    Button {
                        model.installAppleContainer()
                    } label: {
                        if model.installing {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading…") }
                        } else {
                            Label("Install Apple Container", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    .disabled(model.installing)
                }
                Button("Re-check") { model.checkRuntime() }
                    .controlSize(.small)
            }
            Text(runtime.installHint)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(Theme.Spacing.md)
        .cardSurface(radius: Theme.Radius.md)
    }

    // MARK: - Editor & console

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.spec.language.fileName)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)

            MonacoEditorView(
                text: $model.spec.code,
                language: monacoLanguage,
                dark: colorScheme == .dark
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var console: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Output")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if model.isRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                if let note = model.statusNote {
                    Text(note).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)

            ScrollView {
                Text(model.output.isEmpty ? "Run to stream container output here." : model.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(model.output.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
