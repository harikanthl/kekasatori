//
//  PromptLabView.swift
//  MuseDrop
//
//  The Compare arena: run one prompt across several models and watch them stream
//  side by side. Reuses the BYOK LLM stack (LLMRouter) via ArenaService.
//

import SwiftUI

struct PromptLabView: View {
    @StateObject private var model = CompareViewModel()
    @State private var showSystem = false
    @State private var showBrowser = false
    @State private var showHFBrowser = false
    @State private var showRunPodSheet = false
    @State private var showSaveDialog = false
    @State private var saveName = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ScreenHeader(
                    title: "Compare",
                    subtitle: "Run one prompt across models, side by side.",
                    systemImage: "rectangle.split.3x1"
                )
                SectionRule()
                modelBar
                promptControls
            }
            .screenColumn()
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.lg)

            if model.columns.isEmpty {
                EmptyStateView(
                    systemImage: "rectangle.split.3x1",
                    title: "Compare models",
                    message: "Pick models, type a prompt, and Run to stream answers side by side. Cloud models use your key from Settings → AI Providers."
                )
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    runSummaryBar
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            ForEach(model.columns) { column in
                                ArenaColumnView(column: column, cost: model.estimatedCost(for: column))
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.page)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                }
            }
        }
        .sheet(isPresented: $showBrowser) {
            ModelBrowserSheet(
                catalog: model.catalog,
                isAdded: { candidate in model.profiles.contains { $0.sameModel(as: candidate.profile) } },
                onAdd: { model.addProfile($0.profile) },
                onClose: { showBrowser = false }
            )
        }
        .sheet(isPresented: $showHFBrowser) {
            HFModelBrowserSheet(
                isAdded: { hf in model.profiles.contains { $0.preset == .huggingFace && $0.modelId == hf.id } },
                onAdd: { hf in
                    model.addProfile(ModelProfile(label: hf.shortName, preset: .huggingFace, modelId: hf.id))
                },
                onClose: { showHFBrowser = false }
            )
        }
        .sheet(isPresented: $showRunPodSheet) {
            RunPodEndpointSheet(
                onAdd: { model.addProfile($0) },
                onClose: { showRunPodSheet = false }
            )
        }
        .alert("Save prompt set", isPresented: $showSaveDialog) {
            TextField("Name", text: $saveName)
            Button("Save") { model.saveCurrentPrompt(name: saveName) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves your prompt, system prompt, and the \(model.profiles.count) selected model\(model.profiles.count == 1 ? "" : "s"). Reload it anytime from Saved.")
        }
    }

    @ViewBuilder
    private var runSummaryBar: some View {
        if let total = model.totalEstimatedCost {
            HStack(spacing: Theme.Spacing.sm) {
                Label("Est. \(ArenaColumnView.costLabel(total)) this run", systemImage: "dollarsign.circle")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    // MARK: - Model selection

    private var availableToAdd: [ModelProfile] {
        ModelProfile.catalog.filter { candidate in
            !model.profiles.contains { $0.sameModel(as: candidate) }
        }
    }

    private var availableLocalToAdd: [ModelProfile] {
        model.localModels.filter { candidate in
            !model.profiles.contains { $0.sameModel(as: candidate) }
        }
    }

    private var modelBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
        
            Text("Models")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(model.profiles) { profile in
                        modelChip(profile)
                    }
                }
            }

            Menu {
                Button { showBrowser = true } label: {
                    Label("Browse all models…", systemImage: "magnifyingglass")
                }
                Button { showHFBrowser = true } label: {
                    Label("Browse Hugging Face…", systemImage: "sparkles")
                }
                Button { showRunPodSheet = true } label: {
                    Label("Add RunPod endpoint…", systemImage: "cpu")
                }
                Section("Quick add") {
                    ForEach(availableToAdd) { profile in
                        Button(profile.label) { model.addProfile(profile) }
                    }
                }
                if !availableLocalToAdd.isEmpty {
                    Section("Local servers") {
                        ForEach(availableLocalToAdd) { profile in
                            Button(profile.label) { model.addProfile(profile) }
                        }
                    }
                }
                Divider()
                Button { model.refreshLocalModels() } label: {
                    Label("Detect local servers", systemImage: "arrow.clockwise")
                }
            } label: {
                Label("Add", systemImage: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func modelChip(_ profile: ModelProfile) -> some View {
        HStack(spacing: 5) {
            Text(profile.label)
                .font(.caption.weight(.medium))
            Button {
                model.removeProfile(profile.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
        .background(Theme.accent.opacity(0.10), in: Capsule())
    }

    // MARK: - Prompt

    private var promptControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if showSystem {
                TextField("System prompt (optional)", text: $model.systemPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .floatingChrome(radius: Theme.Radius.md)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                TextField("Ask all models the same thing…", text: $model.userPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm + 1)
                    .floatingChrome(radius: Theme.Radius.md)
                    .onSubmit { model.run() }

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

            utilityRow
        }
    }

    private var utilityRow: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button { showSystem.toggle() } label: {
                Label(showSystem ? "Hide system" : "System prompt", systemImage: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            Button {
                saveName = model.suggestedPromptName
                showSaveDialog = true
            } label: {
                Label("Save set", systemImage: "bookmark")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(model.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !model.savedPrompts.isEmpty {
                Menu {
                    ForEach(model.savedPrompts) { saved in
                        Button(savedLabel(saved)) { model.loadPrompt(saved) }
                    }
                    Divider()
                    Menu("Delete") {
                        ForEach(model.savedPrompts) { saved in
                            Button(saved.name, role: .destructive) { model.deletePrompt(saved.id) }
                        }
                    }
                } label: {
                    Label("Saved", systemImage: "bookmark.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    /// Menu label for a saved set — name plus its captured model count.
    private func savedLabel(_ saved: SavedPrompt) -> String {
        guard !saved.models.isEmpty else { return saved.name }
        return "\(saved.name)  ·  \(saved.models.count) model\(saved.models.count == 1 ? "" : "s")"
    }
}

// MARK: - Column

private struct ArenaColumnView: View {
    let column: ArenaColumn
    let cost: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(column.profile.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                statusBadge
            }
            SectionRule()

            ScrollView {
                Group {
                    if let error = column.error {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.danger)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if column.text.isEmpty && column.status == .streaming {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.callout).foregroundStyle(.secondary)
                        }
                    } else {
                        MarkdownMessageView(text: column.text)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .padding(Theme.Spacing.md)
        .frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .cardSurface(radius: Theme.Radius.md)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch column.status {
        case .streaming:
            ProgressView().controlSize(.small)
        case .done:
            StatusPill(text: "Done", systemImage: "checkmark.circle.fill", color: Theme.success)
        case .failed:
            StatusPill(text: "Failed", systemImage: "exclamationmark.triangle.fill", color: Theme.danger)
        case .cancelled:
            StatusPill(text: "Stopped", systemImage: "stop.circle", color: .secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Label(String(format: "%.1fs", column.elapsed), systemImage: "clock")
            Label("~\(column.estimatedTokens) tok", systemImage: "number")
            if let tps = column.tokensPerSecond {
                Label(String(format: "%.0f tok/s", tps), systemImage: "speedometer")
            }
            if let cost {
                Label(Self.costLabel(cost), systemImage: "dollarsign.circle")
            }
            Spacer(minLength: 0)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
    }

    /// Tiny estimated costs need more precision than two decimals.
    static func costLabel(_ cost: Double) -> String {
        if cost < 0.0001 { return "<$0.0001" }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        return String(format: "$%.2f", cost)
    }
}

// MARK: - Model browser

private struct ModelBrowserSheet: View {
    let catalog: [CatalogModel]
    let isAdded: (CatalogModel) -> Bool
    let onAdd: (CatalogModel) -> Void
    let onClose: () -> Void

    @State private var query = ""

    private var filtered: [CatalogModel] {
        guard !query.isEmpty else { return catalog }
        return catalog.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add a model")
                    .font(.headline)
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.md)

            SearchField(placeholder: "Search \(catalog.count) models…", text: $query)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

            Divider()

            if catalog.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Loading the OpenRouter catalog…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { entry in
                    HStack(spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: Theme.Spacing.sm) {
                                if let context = entry.contextLength {
                                    Text("\(context / 1000)K ctx")
                                }
                                Text(entry.pricingLabel)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if isAdded(entry) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                        } else {
                            Button {
                                onAdd(entry)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 560)
    }
}
