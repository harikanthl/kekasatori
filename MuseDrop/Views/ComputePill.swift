//
//  ComputePill.swift
//  MuseDrop
//
//  The compute dial (Phase C): a tactile, *vintage* control — wood grain + brass
//  trim + an amber readout, deliberately styled like an old instrument gauge to
//  contrast the Liquid-Glass cockpit chrome. Tapping it opens the dial: switch
//  targets, promote to GPU, or add a RunPod endpoint. Shows the live cost readout.
//

import SwiftUI

// MARK: - Vintage wooden styling (reusable for any dial control)

enum VintageDial {
    static let woodDark = Color(red: 0.34, green: 0.21, blue: 0.12)
    static let woodLight = Color(red: 0.52, green: 0.34, blue: 0.19)
    static let brass = Color(red: 0.80, green: 0.63, blue: 0.34)
    static let amber = Color(red: 0.99, green: 0.76, blue: 0.38)
    static let parchment = Color(red: 0.98, green: 0.96, blue: 0.90)   // bright cream — legible on wood

    static var wood: LinearGradient {
        LinearGradient(colors: [woodLight, woodDark, woodLight.opacity(0.85)],
                       startPoint: .top, endPoint: .bottom)
    }
    /// A faint diagonal sheen that reads as polished varnish over the grain.
    static var sheen: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// Wraps a control in a wooden, brass-trimmed "dial" face. `active` switches the
    /// readout to a warm amber (used when on a paid GPU target).
    func vintageDial(cornerRadius: CGFloat = 13, padH: CGFloat = 14, padV: CGFloat = 9) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .background(shape.fill(VintageDial.wood))
            .background(shape.fill(VintageDial.sheen))
            .overlay(shape.strokeBorder(VintageDial.brass, lineWidth: 2))
            .overlay(shape.inset(by: 2.5).strokeBorder(.black.opacity(0.20), lineWidth: 0.5))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.30), radius: 4, y: 2)
    }
}

// MARK: - The dial

struct ComputePill: View {
    @ObservedObject var store: ComputeTargetStore
    var accruedCostUSD: Double? = nil
    @State private var showingAdd = false
    // `store.canPromote` reads the Keychain (RunPod/Modal credentials) when a
    // remote endpoint exists. Cache it so the read happens in `.task`, never
    // during body/menu evaluation (which can fire a modal Keychain prompt).
    @State private var canPromote = false

    private var selectionBinding: Binding<UUID> {
        Binding(get: { store.selectedID ?? ComputeTarget.localID },
                set: { store.select($0) })
    }

    var body: some View {
        Menu {
            Picker("Compute", selection: selectionBinding) {
                ForEach(store.targets) { target in
                    Label(target.name, systemImage: target.isLocal ? "laptopcomputer" : "bolt.fill")
                        .tag(target.id)
                }
            }
            .pickerStyle(.inline)

            if canPromote {
                Button {
                    store.promote()
                } label: {
                    Label("Promote to GPU", systemImage: "arrow.up.forward.circle")
                }
            }

            Divider()
            Button {
                showingAdd = true
            } label: {
                Label("Add RunPod endpoint…", systemImage: "plus")
            }
        } label: {
            dialFace
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .sheet(isPresented: $showingAdd) { AddComputeEndpointSheet(store: store) }
        .task { canPromote = store.canPromote }
        .onChange(of: store.saved.count) { _, _ in canPromote = store.canPromote }
        .onChange(of: showingAdd) { _, isOpen in if !isOpen { canPromote = store.canPromote } }
    }

    private var dialFace: some View {
        let target = store.selected
        let paid = target?.isPaid == true
        let rate = ComputeCost.ratePerHour(target?.capabilities.costPerHourUSD)
        let accrued = ComputeCost.accrued(accruedCostUSD)

        return HStack(spacing: 12) {
            // The instrument — a round, brass-ringed gauge face.
            ZStack {
                Circle().fill(VintageDial.wood)
                Circle().strokeBorder(VintageDial.brass, lineWidth: 2)
                Image(systemName: paid ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(paid ? VintageDial.amber : VintageDial.parchment)
            }
            .frame(width: 42, height: 42)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("COMPUTE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(VintageDial.brass)
                Text(target?.name ?? "No compute")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(VintageDial.parchment)
                    .lineLimit(1)
                if let line = accrued ?? rate {
                    Text(accrued != nil ? "spent \(line)" : line)
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(paid ? VintageDial.amber : VintageDial.parchment.opacity(0.92))
                }
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VintageDial.brass)
        }
        .vintageDial()
        .help(paid ? "Running on a paid GPU — cost meter live." : "Local compute (free). Tap to switch or promote.")
    }
}

// MARK: - Add endpoint sheet

struct AddComputeEndpointSheet: View {
    @ObservedObject var store: ComputeTargetStore
    @Environment(\.dismiss) private var dismiss

    @State private var provider: SavedComputeEndpoint.Provider = .runpod
    @State private var name = ""
    @State private var endpoint = ""
    @State private var gpu = "A100 80GB"
    @State private var costText = "1.89"
    @State private var apiKey = ""          // RunPod
    @State private var modalKey = ""        // Modal
    @State private var modalSecret = ""     // Modal

    /// Resolved identifier per provider: a RunPod endpoint id, or a Modal URL.
    private var identifier: String? {
        switch provider {
        case .runpod:
            return RunPodServerless.endpointID(from: endpoint)
        case .modal:
            let t = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: t), url.scheme?.hasPrefix("http") == true else { return nil }
            return t
        }
    }
    private var cost: Double? { Double(costText) }
    private var canSave: Bool {
        identifier != nil && cost != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(VintageDial.amber)
                Text("Add a GPU endpoint")
                    .font(.system(.headline, design: .serif))
                Spacer()
            }

            Form {
                Picker("Provider", selection: $provider) {
                    ForEach(SavedComputeEndpoint.Provider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Name", text: $name, prompt: Text("\(provider.displayName) · A100 80GB"))
                TextField("GPU", text: $gpu)
                TextField("Cost ($/hr)", text: $costText)
                    .frame(maxWidth: 140)

                switch provider {
                case .runpod:
                    TextField("Endpoint ID or URL", text: $endpoint, prompt: Text("abc123xyz"))
                        .font(.callout.monospaced())
                    SecureField("RunPod API key (Keychain)", text: $apiKey)
                case .modal:
                    TextField("Web endpoint URL", text: $endpoint, prompt: Text("https://you--runner.modal.run"))
                        .font(.callout.monospaced())
                    SecureField("Modal-Key (Keychain)", text: $modalKey)
                    SecureField("Modal-Secret (Keychain)", text: $modalSecret)
                }

                if identifier == nil, !endpoint.isEmpty {
                    Text(provider == .runpod ? "Couldn’t read an endpoint id." : "Enter a valid https URL.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                if provider == .runpod {
                    Link("Get an endpoint / key →", destination: URL(string: RunPodServerless.consoleURL)!)
                        .font(.caption)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 480)
    }

    private func save() {
        guard let identifier, let cost else { return }
        switch provider {
        case .runpod:
            let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { _ = KeychainService.set(k, for: KeychainService.Account.runPod) }
        case .modal:
            let k = modalKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let s = modalSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty { _ = KeychainService.set(k, for: KeychainService.Account.modalKey) }
            if !s.isEmpty { _ = KeychainService.set(s, for: KeychainService.Account.modalSecret) }
        }
        store.addEndpoint(SavedComputeEndpoint(
            name: name.trimmingCharacters(in: .whitespaces),
            provider: provider,
            identifier: identifier,
            gpu: gpu.trimmingCharacters(in: .whitespaces),
            costPerHourUSD: cost))
        dismiss()
    }
}
