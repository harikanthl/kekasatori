//
//  SettingsView.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showClearHistoryAlert = false
    @State private var showClearLibraryAlert = false
    @State private var mcpMessage: String?
    @State private var mcpConnecting = false
    private let mcpConnector = MCPServerConnector()
    @State private var kaggleUserInput = KeychainService.get(KeychainService.Account.kaggleUsername) ?? ""
    @State private var kaggleKeyInput = ""
    @State private var kaggleSaved = KeychainService.has(KeychainService.Account.kaggleKey)
    @State private var githubTokenInput = ""
    @State private var githubTokenSaved = KeychainService.has(KeychainService.Account.githubToken)
    @State private var hfTokenInput = ""
    @State private var hfTokenSaved = KeychainService.has(KeychainService.Account.huggingFace)

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
                discoverSourcesSection
                mcpSection
                kaggleSection
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
            Picker("Mode", selection: $themeManager.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }
            .pickerStyle(.segmented)

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
                // RunPod is a per-endpoint Compare/Run target (added from Compare),
                // not a global tutor provider, so it's excluded here.
                ForEach(LLMProviderPreset.allCases.filter { $0 != .runPod }) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .onChange(of: viewModel.llmPreset) { _, _ in
                viewModel.onLLMProviderChanged()
            }

            if viewModel.llmPreset != .onDevice {
                // Base URL — auto-filled for known providers, editable for Custom.
                if viewModel.llmPreset == .custom {
                    TextField("Base URL (OpenAI-compatible)", text: $viewModel.llmBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.saveLLMSettings() }
                } else if !viewModel.llmBaseURL.isEmpty {
                    Label(viewModel.llmBaseURL, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                // Model — free text, a menu of curated + live IDs, and Load models.
                HStack {
                    TextField("Model ID", text: $viewModel.llmModelId)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.saveLLMSettings() }

                    let curated = viewModel.llmPreset.modelSuggestions
                    if !curated.isEmpty || !viewModel.llmLoadedModels.isEmpty {
                        Menu {
                            if !viewModel.llmLoadedModels.isEmpty {
                                Section("Live") {
                                    ForEach(viewModel.llmLoadedModels, id: \.self) { id in
                                        Button(id) {
                                            viewModel.llmModelId = id
                                            viewModel.saveLLMSettings()
                                        }
                                    }
                                }
                            }
                            if !curated.isEmpty {
                                Section("Suggested") {
                                    ForEach(curated, id: \.id) { s in
                                        Button(s.label) {
                                            viewModel.llmModelId = s.id
                                            viewModel.saveLLMSettings()
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Choose a model")
                    }

                    if viewModel.llmPreset.supportsModelListing {
                        if viewModel.llmLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Load models") { Task { await viewModel.loadLLMModels() } }
                                .help("Fetch this provider's current model list (uses your key)")
                        }
                    }
                }
                if let err = viewModel.llmModelsError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // API key.
                HStack {
                    SecureField(viewModel.llmHasKey ? "Key saved — enter to replace" : viewModel.llmPreset.keyHint,
                                text: $viewModel.llmAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { viewModel.saveLLMSettings() }
                        .disabled(viewModel.llmAPIKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if viewModel.llmHasKey {
                        Button("Clear", role: .destructive) { viewModel.clearLLMKey() }
                    }
                }
                HStack(spacing: Theme.Spacing.md) {
                    if viewModel.llmHasKey {
                        Label("Key stored in Keychain", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.success)
                    }
                    if let urlString = viewModel.llmPreset.getKeyURL, let url = URL(string: urlString) {
                        Link("Get a key →", destination: url)
                            .font(.caption)
                    }
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

            Toggle(isOn: $viewModel.llmAnalyzeFigures) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyse figures, charts & tables")
                    Text("Sends pages with figures to your vision-capable cloud model to extract graph data and tables. Off by default — these page images leave your Mac only when enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: viewModel.llmAnalyzeFigures) { _, _ in viewModel.saveLLMSettings() }

            Label(viewModel.llmStatusMessage, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Pick a provider — the base URL fills in automatically and the model menu shows current options (tap Load models for the live list). Keys are stored per-provider in your Keychain and only leave your Mac on requests you send to that provider. Embeddings for RAG run on-device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label {
                Text("**Paper → Podcast** needs a **Google Gemini** key — its multi-speaker audio is Gemini-only. Select **Google Gemini** above to add one; the same key serves Gemini chat and the podcast.")
            } icon: {
                Image(systemName: "waveform.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeader("AI Providers (Tutor)", systemImage: "bubble.left.and.bubble.right", tint: Theme.accent)
        }
    }

    // MARK: - Agents (MCP)

    private var mcpSection: some View {
        Section {
            if mcpConnector.isAvailable, let path = mcpConnector.binaryURL?.path {
                Label("Server ready", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.success)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Embedded MCP server")
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                HStack {
                    Button {
                        mcpConnecting = true
                        mcpMessage = nil
                        Task {
                            let result = await mcpConnector.connectClaudeCode()
                            mcpMessage = result.message
                            mcpConnecting = false
                        }
                    } label: {
                        if mcpConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Add to Claude Code", systemImage: "terminal")
                        }
                    }
                    .disabled(mcpConnecting)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mcpConnector.configJSON(), forType: .string)
                        mcpMessage = "Config copied — paste into Cursor or Claude Desktop’s mcpServers."
                    } label: {
                        Label("Copy config (Cursor / Claude Desktop)", systemImage: "doc.on.doc")
                    }
                }

                if let mcpMessage {
                    Text(mcpMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Lets MCP clients (Claude Code, Cursor, OpenClaw) drive Kekasatori. Currently exposes a scholarly literature search; more tools coming.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Server not found in this build", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                Text("Run a full build of the app so the embedded MCP server is bundled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("Agents (MCP)", systemImage: "point.3.connected.trianglepath.dotted", tint: Theme.accent)
        }
    }

    // MARK: - Learn data (Kaggle)

    private var kaggleSection: some View {
        Section {
            if kaggleSaved {
                Label("Kaggle token saved", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.success)
            }
            TextField("Kaggle username", text: $kaggleUserInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                SecureField(kaggleSaved ? "API key saved — enter to replace" : "Kaggle API key",
                            text: $kaggleKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveKaggle() }
                    .disabled(kaggleUserInput.trimmingCharacters(in: .whitespaces).isEmpty
                              || kaggleKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if kaggleSaved {
                    Button("Clear", role: .destructive) { clearKaggle() }
                }
            }
            Text("Used by Learn's Kaggle data lessons to download real datasets. Create a token at kaggle.com → Settings → API. Stored in your Keychain; sent only to the lesson's container.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeader("Learn data (Kaggle)", systemImage: "tray.and.arrow.down", tint: Theme.accent)
        }
    }

    private func saveKaggle() {
        let user = kaggleUserInput.trimmingCharacters(in: .whitespaces)
        let key = kaggleKeyInput.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !key.isEmpty else { return }
        KeychainService.set(user, for: KeychainService.Account.kaggleUsername)
        KeychainService.set(key, for: KeychainService.Account.kaggleKey)
        kaggleKeyInput = ""
        kaggleSaved = KeychainService.has(KeychainService.Account.kaggleKey)
    }

    private func clearKaggle() {
        KeychainService.delete(KeychainService.Account.kaggleUsername)
        KeychainService.delete(KeychainService.Account.kaggleKey)
        kaggleUserInput = ""
        kaggleKeyInput = ""
        kaggleSaved = false
    }

    // MARK: - Discover search sources (GitHub + HuggingFace)

    private var discoverSourcesSection: some View {
        Section {
            // GitHub
            HStack {
                SecureField(githubTokenSaved ? "GitHub token saved — enter to replace" : "GitHub token (optional)",
                            text: $githubTokenInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let t = githubTokenInput.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    KeychainService.set(t, for: KeychainService.Account.githubToken)
                    githubTokenInput = ""
                    githubTokenSaved = KeychainService.has(KeychainService.Account.githubToken)
                }
                .disabled(githubTokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if githubTokenSaved {
                    Button("Clear", role: .destructive) {
                        KeychainService.delete(KeychainService.Account.githubToken)
                        githubTokenInput = ""
                        githubTokenSaved = false
                    }
                }
            }
            // HuggingFace (shared with HuggingFace inference token)
            HStack {
                SecureField(hfTokenSaved ? "HuggingFace token saved — enter to replace" : "HuggingFace token (optional)",
                            text: $hfTokenInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let t = hfTokenInput.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    KeychainService.set(t, for: KeychainService.Account.huggingFace)
                    hfTokenInput = ""
                    hfTokenSaved = KeychainService.has(KeychainService.Account.huggingFace)
                }
                .disabled(hfTokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if hfTokenSaved {
                    Button("Clear", role: .destructive) {
                        KeychainService.delete(KeychainService.Account.huggingFace)
                        hfTokenInput = ""
                        hfTokenSaved = false
                    }
                }
            }
            Text("Discover searches **GitHub repositories** and **HuggingFace papers** alongside the scholarly sources. Both work without a token — adding one only raises the rate limit. Tokens are stored in your Keychain. Create them at github.com/settings/tokens (no scopes needed) and huggingface.co/settings/tokens. The HuggingFace token is shared with HuggingFace inference.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeader("Discover search sources", systemImage: "magnifyingglass", tint: Theme.accent)
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

                Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                     + ((Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).map { " (\($0))" } ?? ""))
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
