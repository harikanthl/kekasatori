//
//  RunViewModel.swift
//  Kekasatori
//
//  Drives the Run pillar's eval runner (Phase 3a): pick a model (a Compare
//  ModelProfile — cloud BYOK or a detected local server), choose a benchmark
//  harness/task, and run it inside a container, streaming the log live and
//  scraping metrics at the end. Container detection/install mirrors
//  CodeBoxViewModel; command building + parsing live in the pure EvalRunService.
//

import Foundation

@MainActor
final class RunViewModel: ObservableObject {
    @Published var config = EvalConfig()
    @Published var selectedModelID: UUID?
    @Published private(set) var runtime: ContainerRuntimeStatus?
    @Published private(set) var cloudModels: [ModelProfile] = []
    @Published private(set) var localModels: [ModelProfile] = []
    @Published private(set) var log = ""
    @Published private(set) var metrics: [EvalMetric] = []
    @Published private(set) var isRunning = false
    @Published private(set) var installing = false
    @Published private(set) var statusNote: String?
    @Published private(set) var accruedCostUSD: Double?

    /// The compute dial (shared control). Eval-on-GPU isn't portable yet (the
    /// harness `.command` payload isn't remote-portable), so remote targets are
    /// shown but gated; local eval runs through the same backend seam.
    let computeTargets = ComputeTargetStore.shared

    private var backend: ComputeBackend?
    private var runTask: Task<Void, Never>?
    private var currentRun: Run?

    init() {
        // On-device (Apple Intelligence) can't be reached by a container, so the
        // eval picker only offers cloud + local OpenAI-compatible endpoints.
        cloudModels = ModelProfile.loadSelected().filter { $0.preset != .onDevice }
        checkRuntime()
        refreshLocalModels()
    }

    /// Why the Run button is disabled for a remote target (eval portability TODO).
    var remoteEvalNotice: String? {
        (computeTargets.selected?.isLocal == false)
            ? "Benchmarks run locally for now — GPU eval is coming with portable harnesses."
            : nil
    }

    // MARK: - Models

    /// Everything the eval can point a container at: the Compare cloud columns
    /// plus any host-native servers we detected.
    var models: [ModelProfile] { cloudModels + localModels }

    var selectedModel: ModelProfile? { models.first { $0.id == selectedModelID } }

    func refreshLocalModels() {
        Task { @MainActor [weak self] in
            self?.localModels = await LocalInferenceService.shared.detectModels()
        }
    }

    /// Fill the eval config's endpoint/model/key from the chosen profile. Local
    /// profiles carry their own base URL and need no key; cloud profiles use the
    /// preset's base URL and the shared BYOK key from the Keychain.
    func selectModel(_ profile: ModelProfile) {
        selectedModelID = profile.id
        config.modelId = profile.modelId
        // directEndpoint centralizes per-preset base URL + key (local → no key,
        // HF → router + hf token, OpenRouter/custom → BYOK key).
        if let ep = profile.directEndpoint {
            config.endpointBaseURL = ep.baseURL
            config.apiKey = ep.apiKey
        }
    }

    // MARK: - Container runtime (mirrors CodeBoxViewModel)

    func checkRuntime() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await ContainerRuntime.check()
            self.runtime = status
            self.computeTargets.setLocal(from: status)
        }
    }

    var canInstallAppleContainer: Bool {
        ContainerRuntime.supportsAppleContainer && !(runtime?.isReady ?? false) && !installing
    }

    var canStartEngine: Bool { runtime?.engine == .appleContainer && !isRunning }

    func installAppleContainer() {
        guard !installing else { return }
        installing = true
        statusNote = "Downloading Apple Container installer…"
        Task { @MainActor [weak self] in
            do {
                try await ContainerRuntime.downloadAndOpenInstaller()
                self?.statusNote = "Installer opened — finish it, then Re-check & Start engine."
            } catch {
                self?.statusNote = "Couldn’t download the installer: \(error.localizedDescription)"
            }
            self?.installing = false
        }
    }

    func startEngine() {
        guard let status = runtime else { return }
        statusNote = "Starting \(status.engine?.displayName ?? "engine")…"
        Task { @MainActor [weak self] in
            let result = await ContainerRuntime.startSystemService(status)
            self?.statusNote = result.ok ? result.message : "Couldn’t start: \(result.message)"
            self?.checkRuntime()
        }
    }

    // MARK: - Run

    var canRun: Bool {
        !isRunning && (runtime?.isReady ?? false) && selectedModel != nil
            && !config.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !config.endpointBaseURL.isEmpty
            && (computeTargets.selected?.isLocal ?? true)   // eval-on-GPU gated for now
    }

    /// The config we actually run/preview: the chosen config with its endpoint
    /// rewritten so the container can reach a host-local server.
    private var effectiveConfig: EvalConfig {
        var c = config
        if let engine = runtime?.engine {
            c.endpointBaseURL = EvalRunService.containerReachableBaseURL(c.endpointBaseURL, engine: engine)
        }
        return c
    }

    /// Editable command preview (key masked). Empty until an engine is detected.
    var previewCommand: String {
        guard let engine = runtime?.engine else { return "" }
        return EvalRunService.previewCommand(cli: engine.cli, engine: engine, config: effectiveConfig)
    }

    func run() {
        guard canRun, let status = runtime, let engine = status.engine else { return }
        let backend: ComputeBackend
        switch computeTargets.makeBackend(runtime: status) {
        case .success(let b):
            backend = b
        case .failure(let error):
            statusNote = error.message
            return
        }
        let config = effectiveConfig
        log = ""
        metrics = []
        statusNote = nil
        accruedCostUSD = nil
        isRunning = true
        self.backend = backend
        currentRun = Run(workspaceID: WorkspaceStore.shared.selectedID, kind: .harness)

        // Pre-built harness args run through the same backend seam as the CodeBox
        // (the `.command` payload). Local today; GPU once the harness is portable.
        let args = EvalRunService.buildArguments(engine: engine, config: config)
        let request = RunRequest(kind: .harness, payload: .command(args))
        runTask = Task { @MainActor [weak self] in
            do {
                for try await event in backend.launch(request) {
                    self?.currentRun?.apply(event)
                    switch event {
                    case .log(let line):
                        self?.log += line
                    case .cost(let usd):
                        self?.accruedCostUSD = usd
                    case .status(.succeeded):
                        self?.finish(note: "Done.")
                    case .status(.failed(let reason)):
                        self?.finish(note: reason)
                    case .status(.canceled):
                        self?.finish(note: "Stopped.")
                    case .status, .metric, .artifact:
                        break
                    }
                }
            } catch {
                self?.finish(note: error.localizedDescription)
            }
        }
    }

    func stop() {
        runTask?.cancel()
        let backend = self.backend
        Task { await backend?.cancel() }
        finish(note: "Stopped.")
    }

    private func finish(note: String?) {
        // Metrics are advisory — the live log is the source of truth. Scraped on
        // every finish (incl. failure/stop), so partial results still show.
        metrics = EvalRunService.parseResults(log)
        isRunning = false
        statusNote = note
        backend = nil
        runTask = nil
        if var run = currentRun {
            if !run.status.isTerminal { run.apply(.status(.canceled)) }
            RunHistoryStore.shared.record(run)
            if let ws = run.workspaceID { WorkspaceStore.shared.recordRun(run.id, in: ws) }
            MemoryCapture.capture(run)
            currentRun = nil
        }
    }
}
