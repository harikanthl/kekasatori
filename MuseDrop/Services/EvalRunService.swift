//
//  EvalRunService.swift
//  MuseDrop
//
//  Builds and parses container eval runs for the Run pillar. The Python harness
//  (lm-evaluation-harness or inspect-ai) lives inside the image; the host only
//  needs a container engine. Pointed at any OpenAI-compatible endpoint — BYOK
//  cloud, a local Ollama model, or a remote GPU. Command building + result
//  parsing are pure (and tested); streaming is driven by ProcessRunner.
//

import Foundation

struct EvalConfig: Equatable {
    enum Harness: String, CaseIterable, Identifiable {
        case lmEval
        case inspect
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .lmEval:  return "lm-eval-harness"
            case .inspect: return "inspect-ai"
            }
        }
    }

    var harness: Harness = .lmEval
    /// Container image carrying the harness (user-confirmable — no universal default).
    var image: String = "ghcr.io/eleutherai/lm-evaluation-harness:latest"
    var endpointBaseURL: String = ""    // OpenAI-compatible base, e.g. https://openrouter.ai/api/v1
    var modelId: String = ""
    var apiKey: String?
    var task: String = "gsm8k"
    var limit: Int = 20

    /// Common benchmark tasks (the harness accepts many more by name).
    static let commonTasks = ["gsm8k", "hellaswag", "arc_easy", "arc_challenge",
                              "mmlu", "truthfulqa_mc2", "winogrande", "humaneval"]
}

enum EvalRunService {
    /// Container engine arguments: `run --rm [-e …] <image> <harness command>`. Pure.
    static func buildArguments(engine: ContainerEngine, config: EvalConfig) -> [String] {
        var args: [String] = ["run", "--rm"]
        if let key = config.apiKey, !key.isEmpty {
            args += ["-e", "OPENAI_API_KEY=\(key)"]
        }
        if !config.endpointBaseURL.isEmpty {
            args += ["-e", "OPENAI_BASE_URL=\(config.endpointBaseURL)"]
        }
        args.append(config.image)
        args += harnessCommand(config)
        return args
    }

    static func harnessCommand(_ config: EvalConfig) -> [String] {
        switch config.harness {
        case .lmEval:
            return [
                "lm_eval",
                "--model", "local-chat-completions",
                "--model_args", "model=\(config.modelId),base_url=\(config.endpointBaseURL),num_concurrent=2,timeout=120",
                "--tasks", config.task,
                "--limit", String(config.limit)
            ]
        case .inspect:
            return [
                "inspect", "eval", config.task,
                "--model", "openai/\(config.modelId)",
                "--limit", String(config.limit)
            ]
        }
    }

    /// Rewrites a host-loopback endpoint so the harness *inside* the container can
    /// reach a server running on the host (e.g. Ollama on :11434). Docker/Colima
    /// expose the host as `host.docker.internal`; Apple Container has no such alias,
    /// so we leave the URL untouched (point it at a routable address). Pure.
    static func containerReachableBaseURL(_ base: String, engine: ContainerEngine) -> String {
        guard engine == .docker || engine == .colima else { return base }
        return base
            .replacingOccurrences(of: "//localhost", with: "//host.docker.internal")
            .replacingOccurrences(of: "//127.0.0.1", with: "//host.docker.internal")
    }

    /// Human-readable command for the editable preview, with the key masked.
    static func previewCommand(cli: String, engine: ContainerEngine, config: EvalConfig) -> String {
        var masked = config
        if masked.apiKey?.isEmpty == false { masked.apiKey = "••••" }
        return ([cli] + buildArguments(engine: engine, config: masked)).joined(separator: " ")
    }

    /// Best-effort scrape of metric/value pairs from harness stdout. The exact
    /// table format varies by version, so this is advisory — the live log is
    /// the source of truth.
    static func parseResults(_ log: String) -> [EvalMetric] {
        var results: [EvalMetric] = []
        var seen = Set<String>()
        let keywords = ["acc", "acc_norm", "exact_match", "f1", "pass@1", "em", "mc2"]

        for rawLine in log.split(separator: "\n") {
            let line = String(rawLine)
            // Pipe table rows: |task|...|metric|...|0.534|...
            if line.contains("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if let metricIndex = cells.firstIndex(where: { keywords.contains($0) }),
                   let value = cells.dropFirst(metricIndex + 1).compactMap({ Double($0) }).first {
                    let task = cells.first { !$0.isEmpty && Double($0) == nil } ?? cells.first ?? "?"
                    let key = "\(task).\(cells[metricIndex])"
                    if seen.insert(key).inserted {
                        results.append(EvalMetric(label: "\(task) · \(cells[metricIndex])", value: value))
                    }
                }
                continue
            }
            // JSON-ish: "acc": 0.534
            for keyword in keywords {
                if let value = matchMetric(line, key: keyword) {
                    let key = "json.\(keyword)"
                    if seen.insert(key).inserted {
                        results.append(EvalMetric(label: keyword, value: value))
                    }
                }
            }
        }
        return results
    }

    private static func matchMetric(_ line: String, key: String) -> Double? {
        guard let range = line.range(of: "\"\(key)\"") ?? line.range(of: "\(key):") else { return nil }
        let rest = line[range.upperBound...]
        let number = rest.drop { !($0.isNumber || $0 == "-") }.prefix { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(number)
    }
}

struct EvalMetric: Identifiable, Equatable, Codable, Sendable {
    var id: String { label }
    let label: String
    let value: Double
}
