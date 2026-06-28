//
//  ContainerRuntime.swift
//  MuseDrop
//
//  Detects a container engine for the Run pillar's CPU eval harnesses. Prefers
//  Apple's `container` (macOS 26, Apple Silicon), then Docker, then Colima's
//  docker CLI. Mirrors the ManimEnvironment detect/status/install-hint pattern,
//  driven by ProcessRunner.
//

import Foundation
import AppKit

enum ContainerEngine: String, Sendable {
    case appleContainer   // `container` — macOS 26, Apple Silicon
    case docker           // Docker Desktop
    case colima           // Colima (provides the `docker` CLI)

    var displayName: String {
        switch self {
        case .appleContainer: return "Apple Container"
        case .docker:         return "Docker"
        case .colima:         return "Colima"
        }
    }

    /// The CLI used to run containers (Colima drives the docker CLI).
    var cli: String {
        switch self {
        case .appleContainer: return "container"
        case .docker, .colima: return "docker"
        }
    }
}

struct ContainerRuntimeStatus: Sendable {
    let engine: ContainerEngine?
    let executable: URL?

    var isReady: Bool { engine != nil && executable != nil }

    var statusMessage: String {
        if let engine { return "\(engine.displayName) detected" }
        return "No container engine found — install one to run evals"
    }

    var installHint: String {
        """
        Apple Container (macOS 26, Apple Silicon):
          download from github.com/apple/container, install, then:
          container system start
        or Docker Desktop:
          brew install --cask docker
        or Colima (lightweight):
          brew install colima docker && colima start
        """
    }
}

enum ContainerRuntime {
    /// Detect an engine, preferring Apple Container → Docker → Colima.
    static func check() async -> ContainerRuntimeStatus {
        if let url = await which("container") {
            return ContainerRuntimeStatus(engine: .appleContainer, executable: url)
        }
        if let url = await which("docker") {
            // Distinguish Colima-provided docker from Docker Desktop heuristically.
            let engine: ContainerEngine = (await which("colima") != nil) ? .colima : .docker
            return ContainerRuntimeStatus(engine: engine, executable: url)
        }
        return ContainerRuntimeStatus(engine: nil, executable: nil)
    }

    /// Apple Container needs macOS 26 on Apple Silicon.
    static var supportsAppleContainer: Bool {
        #if arch(arm64)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Apple's signed installer pkg (pinned release).
    static let appleContainerInstallerURL = URL(
        string: "https://github.com/apple/container/releases/download/1.0.0/container-1.0.0-installer-signed.pkg"
    )!

    /// Download the signed installer and hand it to macOS Installer (which
    /// verifies the signature and prompts for admin). We never install silently.
    static func downloadAndOpenInstaller() async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: appleContainerInstallerURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ProcessError.executionFailed(
                NSError(domain: "ContainerRuntime", code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))"]))
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-1.0.0-installer-signed.pkg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        await MainActor.run { _ = NSWorkspace.shared.open(destination) }
    }

    /// Start the Apple Container system service (`container system start`).
    /// Idempotent; no-op for Docker/Colima which manage their own daemon.
    static func startSystemService(_ status: ContainerRuntimeStatus) async -> (ok: Bool, message: String) {
        guard status.engine == .appleContainer, let executable = status.executable else {
            return (true, "")
        }
        let runner = ProcessRunner()
        do {
            let result = try await runner.run(executable: executable, arguments: ["system", "start"], timeout: 60)
            if result.exitCode == 0 {
                return (true, "Apple Container started.")
            }
            return (false, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private static func which(_ command: String) async -> URL? {
        let runner = ProcessRunner()
        do {
            let result = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/which"),
                arguments: [command],
                timeout: 5
            )
            guard result.exitCode == 0 else { return nil }
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }
}
