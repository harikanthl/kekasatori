//
//  RunPodEndpointSheet.swift
//  Kekasatori
//
//  Add a RunPod Serverless deployment to the Compare arena (it flows into the Run
//  eval harness too). Unlike the HF router there's no public catalog to browse:
//  the user creates a serverless endpoint in the RunPod console and addresses it
//  by its id, so this is a small form — endpoint id + served model name. The
//  RunPod API key (stored in Keychain) is collected here, like the HF token.
//

import SwiftUI

struct RunPodEndpointSheet: View {
    /// Adds the assembled profile to the arena.
    let onAdd: (ModelProfile) -> Void
    let onClose: () -> Void

    @State private var tokenInput = ""
    @State private var hasToken = KeychainService.has(KeychainService.Account.runPod)
    @State private var endpoint = ""
    @State private var modelId = ""
    @State private var label = ""

    private var previewURL: String? { RunPodServerless.baseURL(forEndpoint: endpoint) }

    private var canAdd: Bool {
        previewURL != nil
            && !modelId.trimmingCharacters(in: .whitespaces).isEmpty
            && hasToken
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    tokenSection
                    endpointSection
                    addBar
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 480)
    }

    private var header: some View {
        HStack {
            Label("Add RunPod endpoint", systemImage: "cpu.fill")
                .font(.headline)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundStyle(.secondary).symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Token

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("RunPod API key", systemImage: hasToken ? "key.fill" : "key",
                         tint: hasToken ? Theme.success : .secondary)
            HStack(spacing: Theme.Spacing.sm) {
                SecureField(hasToken ? "Key saved — enter to replace" : "RunPod API key — needed to run",
                            text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveToken)
                Button("Save", action: saveToken)
                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasToken {
                    Button("Clear", role: .destructive) {
                        KeychainService.delete(KeychainService.Account.runPod)
                        hasToken = false
                    }
                }
                Link(destination: URL(string: RunPodServerless.consoleURL)!) {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Create an endpoint & API key in the RunPod console")
            }
            if hasToken {
                Label("Key stored securely in Keychain", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(Theme.success)
            }
        }
    }

    // MARK: - Endpoint

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("Serverless endpoint", systemImage: "server.rack", tint: .secondary)

            field("Endpoint ID or URL", text: $endpoint,
                  hint: "From the RunPod console — e.g. abc123xyz, or paste the full endpoint URL.")
            if !endpoint.trimmingCharacters(in: .whitespaces).isEmpty {
                Label(previewURL ?? "Couldn’t read an endpoint id from that.",
                      systemImage: previewURL == nil ? "exclamationmark.triangle.fill" : "link")
                    .font(.caption.monospaced())
                    .foregroundStyle(previewURL == nil ? Theme.warning : .secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            field("Model name", text: $modelId,
                  hint: "The model your worker serves — e.g. meta-llama/Llama-3.1-8B-Instruct.")

            field("Label (optional)", text: $label,
                  hint: "Shown on the Compare column. Defaults to the model name.")
        }
    }

    private var addBar: some View {
        HStack {
            if !hasToken {
                Label("Save your RunPod API key to add this endpoint.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add to Compare") {
                if let profile = RunPodServerless.makeProfile(label: label, endpoint: endpoint, modelId: modelId) {
                    onAdd(profile)
                    onClose()
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!canAdd)
        }
    }

    // MARK: - Helpers

    private func saveToken() {
        let t = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        KeychainService.set(t, for: KeychainService.Account.runPod)
        hasToken = KeychainService.has(KeychainService.Account.runPod)
        tokenInput = ""
    }

    private func sectionLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }

    private func field(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
            Text(hint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
