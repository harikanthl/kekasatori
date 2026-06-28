//
//  HFModelBrowserSheet.swift
//  Kekasatori
//
//  Browse the live Hugging Face Inference Providers router catalog and add models
//  to the Compare arena (they flow into the Run eval harness too). Shows per-model
//  owner, modality, max context, and the cheapest live provider's price. The HF
//  token (stored in Keychain) is optional for browsing — the list is public — but
//  required to actually run a model, so we collect it here.
//

import SwiftUI

@MainActor
final class HFCatalogLoader: ObservableObject {
    @Published private(set) var models: [HFRouterModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var hasToken = KeychainService.has(KeychainService.Account.huggingFace)

    func load() {
        isLoading = true
        error = nil
        Task { @MainActor in
            let token = KeychainService.get(KeychainService.Account.huggingFace)
            let list = await HFRouterService.fetchCatalog(token: token)
            models = list.sorted { $0.id.lowercased() < $1.id.lowercased() }
            isLoading = false
            if list.isEmpty { error = "Couldn’t load the catalog — check your connection." }
        }
    }

    func saveToken(_ token: String) {
        KeychainService.set(token, for: KeychainService.Account.huggingFace)
        hasToken = KeychainService.has(KeychainService.Account.huggingFace)
        load()   // re-fetch with the token applied
    }
}

struct HFModelBrowserSheet: View {
    let isAdded: (HFRouterModel) -> Bool
    let onAdd: (HFRouterModel) -> Void
    let onClose: () -> Void

    @StateObject private var loader = HFCatalogLoader()
    @State private var search = ""
    @State private var tokenInput = ""

    private var filtered: [HFRouterModel] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return loader.models }
        return loader.models.filter { $0.id.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tokenRow
            searchRow
            Divider()
            content
        }
        .frame(minWidth: 580, idealWidth: 760, minHeight: 480, idealHeight: 660)
        .onAppear { if loader.models.isEmpty { loader.load() } }
    }

    private var header: some View {
        HStack {
            Label("Hugging Face models", systemImage: "sparkles")
                .font(.headline)
            if loader.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            Text("\(loader.models.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var tokenRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: loader.hasToken ? "key.fill" : "key")
                .foregroundStyle(loader.hasToken ? Theme.success : .secondary)
            SecureField(loader.hasToken ? "HF token saved — enter to replace (hf_…)" : "HF access token (hf_…) — needed to run",
                        text: $tokenInput)
                .textFieldStyle(.plain)
                .onSubmit(saveToken)
            Button("Save", action: saveToken)
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
            Link(destination: URL(string: "https://huggingface.co/settings/tokens")!) {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Create a token on huggingface.co")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var searchRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter by name (e.g. llama, qwen, glm)…", text: $search)
                .textFieldStyle(.plain)
            if loader.error == nil {
                Button { loader.load() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload catalog")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        if let error = loader.error, loader.models.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                Text(error).foregroundStyle(.secondary)
                Button("Retry") { loader.load() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if search.isEmpty && !featured.isEmpty {
                        featuredSection
                    }
                    allModelsSection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    /// "Popular" proxy: the models offered by the most live providers.
    private var featured: [HFRouterModel] {
        Array(loader.models.sorted { $0.liveProviders.count > $1.liveProviders.count }.prefix(10))
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("Popular", systemImage: "sparkles")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.md) {
                    ForEach(featured) { hf in
                        card(hf).frame(width: 210)
                    }
                }
                .padding(.vertical, 4)   // breathing room for card shadows
            }
        }
    }

    private var allModelsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                sectionLabel(search.isEmpty ? "All models" : "Results", systemImage: "square.grid.2x2")
                Spacer()
                Text("\(filtered.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 270), spacing: Theme.Spacing.md)],
                alignment: .leading,
                spacing: Theme.Spacing.md
            ) {
                ForEach(filtered) { card($0) }
            }
        }
    }

    private func card(_ hf: HFRouterModel) -> some View {
        let added = isAdded(hf)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hf.shortName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(hf.ownedBy).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            if hf.isMultimodal || hf.hasFreeProvider {
                HStack(spacing: 4) {
                    if hf.isMultimodal { tag("vision", Theme.accent) }
                    if hf.hasFreeProvider { tag("free", Theme.success) }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let ctx = hf.maxContextLength { metaLabel("\(formatContext(ctx)) context", "arrow.left.and.right") }
                if let p = hf.cheapestProvider { metaLabel(priceLabel(p), "dollarsign.circle") }
                metaLabel("\(hf.liveProviders.count) provider\(hf.liveProviders.count == 1 ? "" : "s")", "server.rack")
            }
            .font(.caption2).foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button { onAdd(hf) } label: {
                Label(added ? "Added" : "Add", systemImage: added ? "checkmark" : "plus")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(added ? Theme.success : Theme.accent)
            .disabled(added)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .cardSurface(radius: Theme.Radius.md)
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func saveToken() {
        let t = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        loader.saveToken(t)
        tokenInput = ""
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private func metaLabel(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 3) { Image(systemName: icon); Text(text) }
    }

    private func priceLabel(_ p: HFRouterModel.Provider) -> String {
        if p.isFree { return "free" }
        guard let i = p.inputPrice, let o = p.outputPrice else { return "—" }
        return String(format: "$%.2f/$%.2f per 1M", i, o)
    }

    private func formatContext(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }
}
