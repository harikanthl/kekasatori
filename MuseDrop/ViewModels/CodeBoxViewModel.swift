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

    private var runner: ProcessRunner?

    init() {
        spec = CodeRunSpec(language: .python, image: "", code: CodeRunSpec.Language.python.starter)
        checkRuntime()
    }

    var canRun: Bool {
        !isRunning && (runtime?.isReady ?? false)
            && !spec.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func checkRuntime() {
        Task { @MainActor [weak self] in
            self?.runtime = await ContainerRuntime.check()
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
        guard !isRunning,
              let status = runtime, status.isReady, let cli = status.executable else {
            statusNote = "No container engine detected — install one to run code."
            return
        }

        let spec = self.spec
        output = ""
        statusNote = nil
        isRunning = true
        let runner = ProcessRunner()
        self.runner = runner

        Task { @MainActor [weak self] in
            do {
                let dir = try CodeRunService.stage(spec)
                defer { try? FileManager.default.removeItem(at: dir) }
                let args = CodeRunService.buildArguments(
                    image: spec.resolvedImage,
                    hostWorkdir: dir.path,
                    runCommand: spec.language.runCommand(file: spec.language.fileName)
                )
                for try await line in runner.runWithProgress(executable: cli, arguments: args) {
                    self?.output += line
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
        isRunning = false
        statusNote = note
        runner = nil
    }
}
