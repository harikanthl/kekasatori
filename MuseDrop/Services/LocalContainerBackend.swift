//
//  LocalContainerBackend.swift
//  MuseDrop
//
//  The local arm of the compute dial. Wraps the existing, battle-tested local
//  path — `CodeRunService.stage` + `buildArguments` + `ProcessRunner.runWithProgress`
//  — behind the `ComputeBackend` seam, mapping each stdout line to a `.log` event
//  and scraping metrics on completion. Behaviour is identical to the old CodeBox
//  path; only the shape changed (docs/cockpit-architecture.md Phase A).
//

import Foundation

final class LocalContainerBackend: ComputeBackend {
    let capabilities: ComputeTarget.Capabilities

    private let cli: URL
    private let engine: ContainerEngine
    private let runner = ProcessRunner()

    /// Fails to build only for a non-local target or a runtime without a CLI.
    init?(target: ComputeTarget, runtime: ContainerRuntimeStatus) {
        guard case .local(let engine) = target.location, let cli = runtime.executable else {
            return nil
        }
        self.engine = engine
        self.cli = cli
        self.capabilities = target.capabilities
    }

    func launch(_ request: RunRequest) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let runner = self.runner
            let cli = self.cli

            let task = Task {
                var stagedDir: URL?
                defer { if let stagedDir { try? FileManager.default.removeItem(at: stagedDir) } }

                do {
                    let args: [String]
                    switch request.payload {
                    case .code(let spec):
                        let dir = try CodeRunService.stage(spec)
                        stagedDir = dir
                        args = CodeRunService.buildArguments(
                            image: spec.resolvedImage,
                            hostWorkdir: dir.path,
                            runCommand: spec.language.runCommand(file: spec.language.fileName),
                            env: spec.env
                        )
                    case .command(let prebuilt):
                        args = prebuilt
                    }

                    continuation.yield(.status(.running))

                    var fullLog = ""
                    for try await line in runner.runWithProgress(executable: cli, arguments: args) {
                        fullLog += line
                        continuation.yield(.log(line))
                    }

                    // Advisory metric scrape (same parser the Run pillar uses).
                    for metric in EvalRunService.parseResults(fullLog) {
                        continuation.yield(.metric(metric))
                    }
                    continuation.yield(.status(.succeeded))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.status(.canceled))
                    continuation.finish()
                } catch let error as ProcessError {
                    let reason: String
                    if case .nonZeroExit(let code, _) = error {
                        reason = "Exited with code \(code)."
                    } else {
                        reason = error.localizedDescription
                    }
                    continuation.yield(.status(.failed(reason)))
                    continuation.finish()
                } catch {
                    continuation.yield(.status(.failed(error.localizedDescription)))
                    continuation.finish()
                }
            }

            // If the consumer stops iterating (or the run is cancelled), tear the
            // subprocess down and cancel the driving task.
            continuation.onTermination = { @Sendable _ in
                runner.cancel()
                task.cancel()
            }
        }
    }

    func cancel() async {
        runner.cancel()
    }
}
