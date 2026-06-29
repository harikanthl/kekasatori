//
//  ComputeTargetStore.swift
//  MuseDrop
//
//  Backing model for the compute dial (Phase C): the local target (from the
//  detected engine) plus any saved RunPod compute endpoints, the current
//  selection, and backend construction for the selected target. Persistence is
//  injectable (UserDefaults) and the RunPod key is read through an injectable
//  provider, so the whole thing is unit-tested without the Keychain or network.
//

import Foundation

@MainActor
final class ComputeTargetStore: ObservableObject {
    /// App-wide dial so a target selected in CodeBox / Run / the agent is the same
    /// everywhere. (Tests construct their own with injected dependencies.)
    static let shared = ComputeTargetStore()

    @Published private(set) var local: ComputeTarget?
    @Published private(set) var saved: [SavedComputeEndpoint]
    @Published var selectedID: UUID?

    private let defaults: UserDefaults
    private let keyProvider: () -> String?
    private let modalProvider: () -> (key: String, secret: String)?
    private static let storageKey = "cockpit.computeEndpoints"

    init(
        defaults: UserDefaults = .standard,
        keyProvider: @escaping () -> String? = { KeychainService.get(KeychainService.Account.runPod) },
        modalProvider: @escaping () -> (key: String, secret: String)? = {
            guard let k = KeychainService.get(KeychainService.Account.modalKey), !k.isEmpty,
                  let s = KeychainService.get(KeychainService.Account.modalSecret), !s.isEmpty
            else { return nil }
            return (k, s)
        }
    ) {
        self.defaults = defaults
        self.keyProvider = keyProvider
        self.modalProvider = modalProvider
        self.saved = Self.load(from: defaults)
        self.selectedID = ComputeTarget.localID   // default to "This Mac"
    }

    // MARK: Targets

    /// All selectable targets, local first.
    var targets: [ComputeTarget] {
        ([local].compactMap { $0 }) + saved.map(\.asTarget)
    }

    /// The current selection, falling back to local when the chosen id is gone.
    var selected: ComputeTarget? {
        targets.first { $0.id == selectedID } ?? local
    }

    /// True once a RunPod API key is present.
    var hasRunPodKey: Bool { keyProvider()?.isEmpty == false }
    /// True once the Modal token pair is present.
    var hasModalCredentials: Bool { modalProvider() != nil }

    /// Whether the target's credentials are available (local is always credential-free).
    func credentialsAvailable(for target: ComputeTarget) -> Bool {
        switch target.location {
        case .local:                       return true
        case .runpodServerless, .runpodPod: return hasRunPodKey
        case .modal:                       return hasModalCredentials
        }
    }

    /// A runnable remote target exists (credentials present), so promote is live.
    var canPromote: Bool {
        targets.contains { !$0.isLocal && credentialsAvailable(for: $0) }
    }

    func select(_ id: UUID) { selectedID = id }

    /// Switch to the first runnable remote target (the dial's one-click promotion).
    func promote() {
        if let remote = targets.first(where: { !$0.isLocal && credentialsAvailable(for: $0) }) {
            selectedID = remote.id
        }
    }

    /// Update the local target after engine detection, preserving selection.
    func setLocal(from runtime: ContainerRuntimeStatus?) {
        local = runtime.flatMap(ComputeTarget.local)
        if selected == nil { selectedID = local?.id }
    }

    // MARK: Saved endpoints (persisted)

    func addEndpoint(_ endpoint: SavedComputeEndpoint) {
        saved.append(endpoint)
        persist()
    }

    func removeEndpoint(_ id: UUID) {
        saved.removeAll { $0.id == id }
        if selectedID == id { selectedID = local?.id ?? ComputeTarget.localID }
        persist()
    }

    // MARK: Backend construction

    enum BackendError: Error, Equatable {
        case noEngine
        case noRunPodKey
        case noModalCredentials
        case unsupported

        var message: String {
            switch self {
            case .noEngine:          return "No container engine detected — install one to run code."
            case .noRunPodKey:       return "Add a RunPod API key in Settings to run on GPU."
            case .noModalCredentials: return "Add your Modal token (key + secret) to run on Modal."
            case .unsupported:       return "This compute target isn’t runnable yet."
            }
        }
    }

    /// Whether the selected target can run right now (drives the Run button).
    func canRunSelected(runtime: ContainerRuntimeStatus?) -> Bool {
        if case .success = makeBackend(runtime: runtime) { return true }
        return false
    }

    /// Build the backend for the selected target.
    func makeBackend(runtime: ContainerRuntimeStatus?) -> Result<ComputeBackend, BackendError> {
        guard let target = selected else { return .failure(.noEngine) }
        switch target.location {
        case .local:
            guard let runtime, let backend = ComputeBackendFactory.make(for: target, runtime: runtime) else {
                return .failure(.noEngine)
            }
            return .success(backend)
        case .runpodServerless:
            guard let key = keyProvider(), !key.isEmpty,
                  let backend = ComputeBackendFactory.makeRunPod(for: target, apiKey: key) else {
                return .failure(.noRunPodKey)
            }
            return .success(backend)
        case .modal(let endpointURL):
            guard let creds = modalProvider() else { return .failure(.noModalCredentials) }
            return .success(ComputeBackendFactory.makeModal(
                capabilities: target.capabilities,
                endpointURL: endpointURL, key: creds.key, secret: creds.secret))
        case .runpodPod:
            return .failure(.unsupported)
        }
    }

    // MARK: Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [SavedComputeEndpoint] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedComputeEndpoint].self, from: data) else {
            return []
        }
        return decoded
    }
}
