//
//  SettingsView.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showClearHistoryAlert = false
    @State private var showClearLibraryAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                title: "Settings",
                subtitle: "Preferences for downloads, study tools, and library",
                systemImage: "gearshape"
            )
            .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.md)

            // Form owns its own scrolling — no outer ScrollView / fixed height.
            Form {
                appearanceSection
                downloadsSection
                aiSection
                aiProvidersSection
                manimSection
                librarySection
                dataManagementSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .onChange(of: viewModel.defaultAudioFormat) { _, _ in
            viewModel.saveSettings()
        }
        .onChange(of: viewModel.defaultVideoResolution) { _, _ in
            viewModel.saveSettings()
        }
        .onChange(of: viewModel.defaultHomeMode) { _, _ in
            viewModel.saveSettings()
        }
        .onChange(of: viewModel.enableAISummary) { _, _ in
            viewModel.saveSettings()
        }
        .onChange(of: viewModel.enableWebResearch) { _, _ in
            viewModel.saveSettings()
        }
        .task {
            await viewModel.refreshManimStatus()
        }
        .onChange(of: viewModel.manimExecutablePath) { _, newValue in
            ManimEnvironment.setCustomExecutablePath(newValue.isEmpty ? nil : newValue)
            viewModel.saveSettings()
            Task { await viewModel.refreshManimStatus() }
        }
        .alert("Clear Download History", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.clearDownloadHistory()
            }
        } message: {
            Text("This will remove all download history. Media files will not be deleted.")
        }
        .alert("Clear Library", isPresented: $showClearLibraryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.clearLibrary()
            }
        } message: {
            Text("This will delete all downloaded media files and history. This action cannot be undone.")
        }
    }

    // MARK: - Downloads

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $themeManager.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(themeManager.theme.accent)
                    .frame(width: 14, height: 14)
                Text(themeManager.theme.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("Appearance", systemImage: "paintpalette", tint: Theme.accent)
        }
    }

    private var downloadsSection: some View {
        Section {
            Picker("Default Audio Format", selection: $viewModel.defaultAudioFormat) {
                ForEach(SettingsViewModel.AudioFormat.allCases, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.menu)

            Picker("Default Video Resolution", selection: $viewModel.defaultVideoResolution) {
                ForEach(SettingsViewModel.VideoResolution.allCases, id: \.self) { resolution in
                    Text(resolution.rawValue).tag(resolution)
                }
            }
            .pickerStyle(.menu)

            Picker("Default Home Mode", selection: $viewModel.defaultHomeMode) {
                Text("Download").tag(ConsumptionMode.download)
                Text("Stream & Study").tag(ConsumptionMode.streamOnly)
            }
            .pickerStyle(.menu)

            Text("Download saves files; Stream & Study keeps a bookmark only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            SectionHeader("Downloads", systemImage: "arrow.down.circle", tint: Theme.accent)
        }
    }

    // MARK: - AI Study Tools

    private var aiSection: some View {
        Section {
            Toggle(isOn: $viewModel.enableAISummary) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable AI Study Tools")
                    Text("Summary, notes, flashcards, mind maps, and key concepts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $viewModel.enableWebResearch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Web research agent")
                    Text("Search the web for topic context to enrich notes (DuckDuckGo)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Uses Apple Foundation Models on-device when Apple Intelligence is enabled. Without it, Kekasatori uses a basic NaturalLanguage fallback — regenerate may look similar until Apple Intelligence is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeader("AI Study Tools", systemImage: "sparkles", tint: Theme.accent)
        }
    }

    // MARK: - AI Providers (Tutor / BYOK)

    private var aiProvidersSection: some View {
        Section {
            Picker("Provider", selection: $viewModel.llmPreset) {
                ForEach(LLMProviderPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: viewModel.llmPreset) { _, newValue in
                if let base = newValue.defaultBaseURL, newValue != .custom {
                    viewModel.llmBaseURL = base
                }
                viewModel.saveLLMSettings()
            }

            if viewModel.llmPreset != .onDevice {
                HStack {
                    TextField("Model ID", text: $viewModel.llmModelId)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.saveLLMSettings() }
                    if viewModel.llmPreset == .openRouter {
                        Menu {
                            ForEach(LLMModelPreset.openRouterSuggestions, id: \.id) { suggestion in
                                Button(suggestion.label) {
                                    viewModel.llmModelId = suggestion.id
                                    viewModel.saveLLMSettings()
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Suggested models")
                    }
                }

                if viewModel.llmPreset == .custom {
                    TextField("Base URL (OpenAI-compatible)", text: $viewModel.llmBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.saveLLMSettings() }
                }

                HStack {
                    SecureField(viewModel.llmHasKey ? "API key saved — enter to replace" : "API key", text: $viewModel.llmAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { viewModel.saveLLMSettings() }
                        .disabled(viewModel.llmAPIKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if viewModel.llmHasKey {
                        Button("Clear", role: .destructive) { viewModel.clearLLMKey() }
                    }
                }
                if viewModel.llmHasKey {
                    Label("Key stored securely in Keychain", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                }

                Toggle("Prefer on-device when available", isOn: $viewModel.llmPreferOnDevice)
                    .onChange(of: viewModel.llmPreferOnDevice) { _, _ in viewModel.saveLLMSettings() }
            }

            Toggle(isOn: $viewModel.llmEnableRAG) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ground answers in the source (RAG)")
                    Text("Retrieves the most relevant passages from the paper or transcript for each question.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: viewModel.llmEnableRAG) { _, _ in viewModel.saveLLMSettings() }

            Label(viewModel.llmStatusMessage, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Keys never leave your Mac except on requests you send to your chosen provider. Embeddings for RAG run on-device. Get an OpenRouter key at openrouter.ai.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeader("AI Providers (Tutor)", systemImage: "bubble.left.and.bubble.right", tint: Theme.accent)
        }
    }

    // MARK: - Math Animations (Manim)

    private var manimSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status")
                    Text(viewModel.manimStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                StatusPill(
                    text: viewModel.manimIsReady ? "Ready" : "Not ready",
                    systemImage: viewModel.manimIsReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    color: viewModel.manimIsReady ? Theme.success : Theme.warning
                )
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Manim executable")
                TextField("/opt/homebrew/bin/manim", text: $viewModel.manimExecutablePath)
                    .textFieldStyle(.roundedBorder)
                Text("Optional override — leave empty to auto-detect Homebrew install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Install Manim and LaTeX")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("brew install manim\nbrew install --cask basictex\nsudo tlmgr install amsfonts standalone preview dvisvgm")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            SectionHeader("Math Animations (Manim)", systemImage: "function", tint: Theme.accent)
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Location")
                Text(viewModel.libraryLocation.path)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            SectionHeader("Library", systemImage: "folder", tint: Theme.accent)
        }
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        Section {
            Button(role: .destructive) {
                showClearHistoryAlert = true
            } label: {
                DataManagementRow(
                    title: "Clear Download History",
                    subtitle: "Remove history, keep media files"
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showClearLibraryAlert = true
            } label: {
                DataManagementRow(
                    title: "Clear Library",
                    subtitle: "Delete all files and history"
                )
            }
            .buttonStyle(.plain)
        } header: {
            SectionHeader("Data Management", systemImage: "externaldrive", tint: Theme.accent)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.md) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Kekasatori")
                        .font(.headline)
                    Text("Turn videos, papers, and articles into study material")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Version 1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("About", systemImage: "info.circle", tint: Theme.accent)
        }
    }
}

// MARK: - Data Management Row

private struct DataManagementRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.danger)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
