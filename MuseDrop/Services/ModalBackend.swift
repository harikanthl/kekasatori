//
//  ModalBackend.swift
//  MuseDrop
//
//  Second GPU provider for the compute dial (per docs/gpu-providers.md). Modal's
//  Sandboxes run *arbitrary* commands on a GPU, but Modal is SDK-only (Python/JS/
//  Go) — there is no public REST API — so a desktop client drives it the same way
//  as RunPod: a deployed **Modal web endpoint** (authed with `Modal-Key` /
//  `Modal-Secret` headers) that accepts a `ContainerJobSpec`, runs it in a sandbox,
//  and returns stdout + exit code.
//
//  Modal web endpoints are request/response, so this backend runs synchronously
//  (no mid-run polling) and maps the result to the shared `RunEvent` stream. The
//  orchestration is driven by an injectable `ModalRunner` → fake-tested without
//  network or a Modal account. The live `ModalHTTPClient` is built but unverified
//  until a token + deployed runner endpoint exist.
//

import Foundation

struct ModalRunResult: Equatable, Sendable {
    var output: String
    var exitCode: Int
}

protocol ModalRunner: Sendable {
    func run(_ spec: ContainerJobSpec) async throws -> ModalRunResult
}

final class ModalBackend: ComputeBackend, @unchecked Sendable {
    let capabilities: ComputeTarget.Capabilities

    private let runner: ModalRunner
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(capabilities: ComputeTarget.Capabilities, runner: ModalRunner) {
        self.capabilities = capabilities
        self.runner = runner
    }

    func launch(_ request: RunRequest) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let started = Task {
                guard let spec = ContainerJobSpec.from(request) else {
                    continuation.yield(.status(.failed(
                        "This run isn’t portable to Modal yet — promote a code/spec run instead.")))
                    continuation.finish()
                    return
                }

                let start = Date()
                func emitCost() {
                    if let c = RunPodBackend.cost(elapsed: Date().timeIntervalSince(start),
                                                  ratePerHourUSD: self.capabilities.costPerHourUSD) {
                        continuation.yield(.cost(c))
                    }
                }

                continuation.yield(.status(.provisioning))
                continuation.yield(.status(.running))
                do {
                    let result = try await self.runner.run(spec)
                    if !result.output.isEmpty { continuation.yield(.log(result.output)) }
                    if result.exitCode == 0 {
                        for metric in EvalRunService.parseResults(result.output) {
                            continuation.yield(.metric(metric))
                        }
                        emitCost()
                        continuation.yield(.status(.succeeded))
                    } else {
                        emitCost()
                        continuation.yield(.status(.failed("Exited with code \(result.exitCode).")))
                    }
                } catch is CancellationError {
                    continuation.yield(.status(.canceled))
                } catch let error as URLError where error.code == .cancelled {
                    continuation.yield(.status(.canceled))
                } catch {
                    continuation.yield(.status(.failed(error.localizedDescription)))
                }
                continuation.finish()
            }
            lock.lock(); task = started; lock.unlock()
            continuation.onTermination = { @Sendable _ in started.cancel() }
        }
    }

    func cancel() async {
        currentTask()?.cancel()
    }

    /// Synchronous accessor so the lock is never held across an `await`.
    private func currentTask() -> Task<Void, Never>? {
        lock.lock(); defer { lock.unlock() }
        return task
    }
}

// MARK: - Live HTTP adapter (unverified until token + endpoint exist)

/// Calls a deployed Modal web endpoint that runs a `ContainerJobSpec` in a GPU
/// sandbox and returns `{ output / stdout, exit_code / returncode }`. Auth is
/// Modal's proxy token pair (`Modal-Key` / `Modal-Secret` headers).
struct ModalHTTPClient: ModalRunner {
    let endpointURL: String
    let key: String
    let secret: String
    var session: URLSession = .shared

    func run(_ spec: ContainerJobSpec) async throws -> ModalRunResult {
        guard let url = URL(string: endpointURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "Modal-Key")
        req.setValue(secret, forHTTPHeaderField: "Modal-Secret")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(spec)

        let (data, _) = try await session.data(for: req)
        struct Resp: Decodable {
            let output: String?; let stdout: String?
            let exit_code: Int?; let returncode: Int?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return ModalRunResult(output: r.output ?? r.stdout ?? "",
                              exitCode: r.exit_code ?? r.returncode ?? 0)
    }
}

extension ComputeBackendFactory {
    /// Build the Modal backend for a deployed runner endpoint + token pair.
    static func makeModal(
        capabilities: ComputeTarget.Capabilities,
        endpointURL: String,
        key: String,
        secret: String
    ) -> ModalBackend {
        let runner = ModalHTTPClient(endpointURL: endpointURL, key: key, secret: secret)
        return ModalBackend(capabilities: capabilities, runner: runner)
    }
}
