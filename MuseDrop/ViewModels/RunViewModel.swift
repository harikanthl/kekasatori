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

    private var runner: ProcessRunner?

    init() {
        // On-device (Apple Intelligence) can't be reached by a container, so the
        // eval picker only offers cloud + local OpenAI-compatible endpoints.
        cloudModels = ModelProfile.loadSelected().filter { $0.preset != .onDevice }
        checkRuntime()
        refreshLocalModels()
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
            self?.runtime = await ContainerRuntime.check()
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
        guard canRun, let status = runtime, let cli = status.executable, let engine = status.engine else { return }
        let config = effectiveConfig
        log = ""
        metrics = []
        statusNote = nil
        isRunning = true
        let runner = ProcessRunner()
        self.runner = runner

        let args = EvalRunService.buildArguments(engine: engine, config: config)
        Task { @MainActor [weak self] in
            do {
                for try await line in runner.runWithProgress(executable: cli, arguments: args) {
                    self?.log += line
                }
                self?.finish(note: "Done.")
            } catch is CancellationError {
                self?.finish(note: "Stopped.")
            } catch let error as ProcessError {
                if case .nonZeroExit(let code, _) = error {
                    self?.finish(note: "Exited with code \(code).")
                } else {
                    self?.finish(note: error.localizedDescription)
                }
            } catch {
                self?.finish(note: error.localizedDescription)
            }
        }
    }

    func stop() {
        runner?.cancel()
        runner = nil
        finish(note: "Stopped.")
    }

    private func finish(note: String?) {
        // Metrics are advisory — the live log is the source of truth.
        metrics = EvalRunService.parseResults(log)
        isRunning = false
        statusNote = note
        runner = nil
    }
}
