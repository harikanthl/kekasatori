//
//  CodeBoxViewModel.swift
//  MuseDrop
//
//  Drives the Code box: holds the snippet + chosen image, detects a container
//  engine, and runs the code in a container streaming output. (Local is CPU
//  only; a remote GPU push is a later step.)
//

import Foundation

@MainActor
final class CodeBoxViewModel: ObservableObject {
    @Published var spec: CodeRunSpec
    @Published private(set) var output: String = ""
    @Published private(set) var isRunning = false
    @Published private(set) var runtime: ContainerRuntimeStatus?
    @Published private(set) var statusNote: String?
    @Published private(set) var accruedCostUSD: Double?
    /// Set when the user hits Run on a paid GPU target — the view confirms first.
    @Published var pendingPaidConfirm = false

    /// The compute dial: which target (local ↔ GPU) the next run uses. App-wide,
    /// so a target picked here also applies in Run and the agent.
    let computeTargets = ComputeTargetStore.shared
    /// Optional spend ceiling for a single paid run (RunGuard stops past it).
    var costCapUSD: Double?

    private var backend: ComputeBackend?
    private var runTask: Task<Void, Never>?
    private var guardTask: Task<Void, Never>?
    /// The run record assembled from the event stream, saved to history on finish.
    private var currentRun: Run?

    init() {
        spec = CodeRunSpec(language: .python, image: "", code: CodeRunSpec.Language.python.starter)
        checkRuntime()
    }

    var canRun: Bool {
        !isRunning
            && !spec.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && computeTargets.canRunSelected(runtime: runtime)
    }

    func checkRuntime() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await ContainerRuntime.check()
            self.runtime = status
            self.computeTargets.setLocal(from: status)
        }
    }

    @Published private(set) var installing = false

    /// Only meaningful for Apple Container (Docker/Colima run their own daemon).
    var canStartEngine: Bool { runtime?.engine == .appleContainer && !isRunning }

    /// Offer the Apple Container installer when none is detected and the Mac supports it.
    var canInstallAppleContainer: Bool {
        ContainerRuntime.supportsAppleContainer && !(runtime?.isReady ?? false) && !installing
    }

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

    /// Reset the editor to the selected language's starter when it's empty.
    func loadStarterIfEmpty() {
        if spec.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            spec.code = spec.language.starter
        }
    }

    func run() {
        guard !isRunning else { return }
        // A paid GPU target needs an explicit confirm before we spend money.
        if computeTargets.selected?.isPaid == true {
            pendingPaidConfirm = true
            return
        }
        launch()
    }

    /// Confirmed launch on a paid target (called from the confirmation dialog).
    func confirmPaidRun() {
        pendingPaidConfirm = false
        launch()
    }

    private func launch() {
        let backend: ComputeBackend
        switch computeTargets.makeBackend(runtime: runtime) {
        case .success(let b):
            backend = b
        case .failure(let error):
            statusNote = error.message
            return
        }

        output = ""
        statusNote = nil
        accruedCostUSD = nil
        isRunning = true
        self.backend = backend
        currentRun = Run(workspaceID: WorkspaceStore.shared.selectedID, kind: .script)

        let request = RunRequest.code(spec)
        let target = computeTargets.selected
        let costCap = costCapUSD
        let start = Date()

        runTask = Task { @MainActor [weak self] in
            do {
                for try await event in backend.launch(request) {
                    guard let self else { break }
                    self.currentRun?.apply(event)
                    switch event {
                    case .log(let line):
                        self.output += line
                    case .cost(let usd):
                        self.accruedCostUSD = usd
                        if RunGuard.shouldStop(elapsed: Date().timeIntervalSince(start),
                                               maxRuntime: target?.capabilities.maxRuntime,
                                               costUSD: usd, costCapUSD: costCap) {
                            self.stop(note: "Stopped — over budget/time guard.")
                        }
                    case .status(.succeeded):
                        self.finish(note: "Done.")
                    case .status(.failed(let reason)):
                        self.finish(note: reason)
                    case .status(.canceled):
                        self.finish(note: "Stopped.")
                    case .status, .metric, .artifact:
                        break
                    }
                }
            } catch {
                self?.finish(note: error.localizedDescription)
            }
        }

        // Hard stop at the target's max runtime (e.g. a paid pod), if any.
        if let maxRuntime = target?.capabilities.maxRuntime {
            guardTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(maxRuntime * 1_000_000_000))
                if self?.isRunning == true { self?.stop(note: "Stopped — reached max runtime.") }
            }
        }
    }

    func stop() { stop(note: "Stopped.") }

    private func stop(note: String) {
        runTask?.cancel()
        let backend = self.backend
        Task { await backend?.cancel() }
        finish(note: note)
    }

    private func finish(note: String?) {
        isRunning = false
        statusNote = note
        backend = nil
        runTask = nil
        guardTask?.cancel()
        guardTask = nil
        if var run = currentRun {
            if !run.status.isTerminal { run.apply(.status(.canceled)) }
            RunHistoryStore.shared.record(run)
            if let ws = run.workspaceID { WorkspaceStore.shared.recordRun(run.id, in: ws) }
            MemoryCapture.capture(run)
            currentRun = nil
        }
    }
}
