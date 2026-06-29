//
//  RunPodBackend.swift
//  MuseDrop
//
//  The remote arm of the compute dial: an ephemeral RunPod serverless GPU job
//  behind the same `ComputeBackend` seam as the local container backend, so
//  "promote to GPU" is a target swap (docs/cockpit-architecture.md Phase B).
//
//  The job lifecycle (submit → poll → output/cancel) is driven through an
//  injectable `RunPodJobClient`, so the orchestration — status→RunEvent mapping,
//  cost metering, teardown — is fully unit-tested with a fake (RunPodBackendTests)
//  without touching the network or spending GPU money. `RunPodHTTPClient` is the
//  live adapter; it targets a RunPod serverless **code-runner** endpoint and is
//  wired only once the user supplies an endpoint id + API key (Phase C UI). The
//  `.command` (raw docker-args) payload is local-only for now; remote runs use the
//  portable `.code` payload, which carries image/command/env/files semantically.
//

import Foundation

// MARK: - Job transport

/// Normalised job state the backend understands, decoupled from RunPod's wire
/// status strings (IN_QUEUE / IN_PROGRESS / COMPLETED / FAILED / CANCELLED).
enum RunPodJobState: Equatable, Sendable {
    case inQueue
    case inProgress(log: String?)
    case completed(output: String)
    case failed(String)
    case canceled
}

protocol RunPodJobClient: Sendable {
    func submit(_ spec: ContainerJobSpec) async throws -> String   // → job id
    func poll(jobID: String) async throws -> RunPodJobState
    func cancel(jobID: String) async throws
}

// MARK: - Backend

final class RunPodBackend: ComputeBackend, @unchecked Sendable {
    let capabilities: ComputeTarget.Capabilities

    private let client: RunPodJobClient
    private let pollSeconds: Double
    private let lock = NSLock()
    private var jobID: String?
    private var cancelled = false

    init(target: ComputeTarget, client: RunPodJobClient, pollSeconds: Double = 2) {
        self.capabilities = target.capabilities
        self.client = client
        self.pollSeconds = pollSeconds
    }

    /// Map a portable request to a job spec (delegates to the shared mapper).
    static func makeInput(from request: RunRequest) -> ContainerJobSpec? {
        ContainerJobSpec.from(request)
    }

    /// Pure cost meter: elapsed wall-time × hourly rate. Nil when the target is
    /// free or the rate is unknown.
    static func cost(elapsed: TimeInterval, ratePerHourUSD: Double?) -> Double? {
        guard let rate = ratePerHourUSD, rate > 0 else { return nil }
        return rate * (elapsed / 3600)
    }

    func launch(_ request: RunRequest) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let input = Self.makeInput(from: request) else {
                    continuation.yield(.status(.failed(
                        "This run isn’t portable to RunPod yet — promote a code/spec run instead.")))
                    continuation.finish()
                    return
                }

                let start = Date()
                func emitCost() {
                    if let c = Self.cost(elapsed: Date().timeIntervalSince(start),
                                         ratePerHourUSD: self.capabilities.costPerHourUSD) {
                        continuation.yield(.cost(c))
                    }
                }

                do {
                    continuation.yield(.status(.provisioning))
                    let id = try await self.client.submit(input)
                    self.setJob(id)
                    var didRun = false

                    poll: while true {
                        if self.isCancelled {
                            try? await self.client.cancel(jobID: id)
                            emitCost()
                            continuation.yield(.status(.canceled))
                            break poll
                        }

                        switch try await self.client.poll(jobID: id) {
                        case .inQueue:
                            break
                        case .inProgress(let log):
                            if !didRun { didRun = true; continuation.yield(.status(.running)) }
                            if let log, !log.isEmpty { continuation.yield(.log(log)) }
                        case .completed(let output):
                            if !didRun { continuation.yield(.status(.running)) }
                            if !output.isEmpty { continuation.yield(.log(output)) }
                            for metric in EvalRunService.parseResults(output) {
                                continuation.yield(.metric(metric))
                            }
                            emitCost()
                            continuation.yield(.status(.succeeded))
                            break poll
                        case .failed(let message):
                            emitCost()
                            continuation.yield(.status(.failed(message)))
                            break poll
                        case .canceled:
                            emitCost()
                            continuation.yield(.status(.canceled))
                            break poll
                        }

                        if self.pollSeconds > 0 {
                            try await Task.sleep(nanoseconds: UInt64(self.pollSeconds * 1_000_000_000))
                        }
                        try Task.checkCancellation()
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.status(.canceled))
                    continuation.finish()
                } catch {
                    continuation.yield(.status(.failed(error.localizedDescription)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func cancel() async {
        if let id = markCancelled() {
            try? await client.cancel(jobID: id)
        }
    }

    /// Flag cancellation and return the live job id (if submitted) — synchronous so
    /// the lock is never held across an `await`.
    private func markCancelled() -> String? {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        return jobID
    }

    private func setJob(_ id: String) { lock.lock(); jobID = id; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

// MARK: - Live HTTP adapter (unverified until key + endpoint are wired)

/// Calls RunPod's serverless jobs API. Requires a deployed **code-runner**
/// endpoint that understands `ContainerJobSpec` and returns its stdout as the job
/// `output`. Built but not yet exercised end-to-end (needs the user's endpoint id
/// + API key — wired in Phase C). The orchestration above is what's tested; this
/// is a thin, replaceable transport.
struct RunPodHTTPClient: RunPodJobClient {
    let endpointID: String
    let apiKey: String
    var session: URLSession = .shared

    private func request(_ path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard let base = RunPodServerless.jobsBaseURL(endpointID: endpointID),
              let url = URL(string: base + path) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    func submit(_ spec: ContainerJobSpec) async throws -> String {
        let payload = try JSONEncoder().encode(["input": spec])
        let (data, _) = try await session.data(for: request("/run", method: "POST", body: payload))
        struct Submit: Decodable { let id: String }
        return try JSONDecoder().decode(Submit.self, from: data).id
    }

    func poll(jobID: String) async throws -> RunPodJobState {
        let (data, _) = try await session.data(for: request("/status/\(jobID)", method: "GET"))
        struct Status: Decodable { let status: String; let output: JSONValue?; let error: String? }
        // Status values per RunPod serverless docs (2026): IN_QUEUE, IN_PROGRESS /
        // RUNNING, COMPLETED, FAILED, CANCELLED, TIMED_OUT.
        let s = try JSONDecoder().decode(Status.self, from: data)
        switch s.status.uppercased() {
        case "IN_QUEUE":                 return .inQueue
        case "IN_PROGRESS", "RUNNING":   return .inProgress(log: s.output?.asLogString)
        case "COMPLETED":                return .completed(output: s.output?.asLogString ?? "")
        case "FAILED":                   return .failed(s.error ?? "RunPod job failed")
        case "TIMED_OUT":                return .failed("RunPod job timed out")
        case "CANCELLED", "CANCELED":    return .canceled
        default:                         return .inProgress(log: nil)
        }
    }

    func cancel(jobID: String) async throws {
        _ = try await session.data(for: request("/cancel/\(jobID)", method: "POST"))
    }
}

/// Minimal JSON wrapper so an arbitrary handler `output` (string or object) can be
/// flattened to a log string without committing to a fixed schema.
enum JSONValue: Decodable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s) } else { self = .other }
    }

    var asLogString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

extension ComputeBackendFactory {
    /// Build the RunPod backend for a serverless target, given an API key. Returns
    /// nil for non-serverless targets (pods arrive in Phase D).
    static func makeRunPod(for target: ComputeTarget, apiKey: String, pollSeconds: Double = 2) -> RunPodBackend? {
        guard case .runpodServerless(let endpointID) = target.location else { return nil }
        let client = RunPodHTTPClient(endpointID: endpointID, apiKey: apiKey)
        return RunPodBackend(target: target, client: client, pollSeconds: pollSeconds)
    }
}
