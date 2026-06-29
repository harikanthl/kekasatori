//
//  AgentTools.swift
//  MuseDrop
//
//  Phase G.3: the tools the agent can call, and the parser for a ReAct-style
//  loop. We don't depend on provider-native function-calling — the model emits a
//  `TOOL <name> {json}` line in plain text, we parse + execute it, feed the result
//  back, and repeat until it answers. The G.3 toolset is read + memory-write +
//  graph-write only (safe, no spend); launching runs / provisioning GPUs is G.4,
//  gated behind an approval step.
//

import Foundation

/// A parsed tool invocation from model text.
struct ToolCall: Equatable {
    var name: String
    var args: [String: String]

    /// Parse `TOOL <name> {json-args}` appearing anywhere in `text`. Lenient:
    /// missing/!valid JSON yields empty args; returns nil when there's no call.
    static func parse(_ text: String) -> ToolCall? {
        guard let marker = text.range(of: "TOOL ") else { return nil }
        let rest = text[marker.upperBound...]
        let afterSpaces = rest.drop { $0 == " " }
        guard let nameEnd = afterSpaces.firstIndex(where: { $0 == " " || $0 == "{" || $0 == "\n" }) else {
            let name = String(afterSpaces).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : ToolCall(name: name, args: [:])
        }
        let name = String(afterSpaces[..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        guard let braceStart = afterSpaces[nameEnd...].firstIndex(of: "{"),
              let braceEnd = afterSpaces.lastIndex(of: "}"), braceStart < braceEnd else {
            return ToolCall(name: name, args: [:])
        }
        let json = String(afterSpaces[braceStart...braceEnd])
        var args: [String: String] = [:]
        if let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in object { args[key] = "\(value)" }
        }
        return ToolCall(name: name, args: args)
    }
}

/// A side-effecting action the agent *proposes* — the human approves before it
/// runs (G.4 approval gate). The effect is carried as data so execution is
/// injectable + testable.
struct PendingAction: Identifiable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var kind: Kind

    enum Kind: Equatable {
        case switchCompute(UUID)        // ComputeTarget id
        case launchRun(CodeRunSpec)     // code to run on the selected target
    }

    init(id: UUID = UUID(), title: String, detail: String, kind: Kind) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
    }
}

@MainActor
protocol AgentTool {
    var name: String { get }
    /// One line for the system prompt: name(args) — what it does.
    var spec: String { get }
    func run(_ args: [String: String]) async -> String
}

// MARK: - Concrete tools (safe: read + memory/graph write)

struct MemorySearchTool: AgentTool {
    let memory: any MemoryStore
    var name: String { "memory_search" }
    var spec: String { "memory_search {\"query\": \"…\"} — recall relevant past runs/facts/notes." }
    func run(_ args: [String: String]) async -> String {
        let hits = memory.recall(MemoryQuery(text: args["query"] ?? "", limit: 5))
        guard !hits.isEmpty else { return "no matching memories" }
        return hits.map { "- \($0.content)" }.joined(separator: "\n")
    }
}

struct MemoryWriteTool: AgentTool {
    let memory: any MemoryStore
    let scope: MemoryScope
    var name: String { "memory_write" }
    var spec: String { "memory_write {\"content\": \"…\"} — save a durable fact for later." }
    func run(_ args: [String: String]) async -> String {
        let content = (args["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return "nothing to save" }
        memory.remember(RawObservation(text: content, kind: .semantic, source: .agentStep, scope: scope))
        return "saved"
    }
}

struct RecentRunsTool: AgentTool {
    let history: RunHistoryStore
    let workspace: Workspace?
    var name: String { "recent_runs" }
    var spec: String { "recent_runs {} — list recent runs (status + metrics) for this workspace." }
    func run(_ args: [String: String]) async -> String {
        let runs = workspace.map { history.forWorkspace($0.id) } ?? history.recent(5)
        guard !runs.isEmpty else { return "no runs yet" }
        return runs.prefix(5).map { "- \($0.kind.rawValue): \(AgentPrompt.statusWord($0.status))" }
            .joined(separator: "\n")
    }
}

struct RememberFactTool: AgentTool {
    let graph: KnowledgeGraphStore
    var name: String { "remember_fact" }
    var spec: String { "remember_fact {\"subject\":\"…\",\"predicate\":\"…\",\"object\":\"…\"} — add a relationship to the knowledge graph." }
    func run(_ args: [String: String]) async -> String {
        let subject = (args["subject"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = (args["predicate"] ?? "relates-to").trimmingCharacters(in: .whitespacesAndNewlines)
        let object = (args["object"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !object.isEmpty else { return "need a subject and object" }
        let from = graph.upsertEntity(type: .concept, name: subject)
        let to = graph.upsertEntity(type: .concept, name: object)
        graph.assert(from: from.id, predicate: predicate, to: to.id)
        return "remembered: \(subject) \(predicate) \(object)"
    }
}

// MARK: - Gated action tools (propose only; human approves)

struct SwitchComputeTool: AgentTool {
    let targets: ComputeTargetStore
    let propose: @MainActor (PendingAction) -> Void
    var name: String { "switch_compute" }
    var spec: String { "switch_compute {\"target\": \"…\"} — propose switching the compute target (e.g. a GPU). Requires approval." }
    func run(_ args: [String: String]) async -> String {
        let query = (args["target"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = targets.targets.first(where: { $0.name.localizedCaseInsensitiveContains(query) }) else {
            let names = targets.targets.map(\.name).joined(separator: ", ")
            return "no target matching “\(query)”. Available: \(names)"
        }
        propose(PendingAction(title: "Switch compute to \(target.name)",
                              detail: target.isPaid ? "Paid GPU target." : "Local target.",
                              kind: .switchCompute(target.id)))
        return "proposed switch to \(target.name) (awaiting approval)"
    }
}

struct LaunchRunTool: AgentTool {
    let propose: @MainActor (PendingAction) -> Void
    var name: String { "launch_run" }
    var spec: String { "launch_run {\"code\": \"…\", \"image\": \"(optional)\"} — propose running Python on the selected target. Requires approval." }
    func run(_ args: [String: String]) async -> String {
        let code = (args["code"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return "no code to run" }
        let spec = CodeRunSpec(language: .python, image: args["image"] ?? "", code: code)
        propose(PendingAction(title: "Run code on the selected target",
                              detail: String(code.prefix(140)),
                              kind: .launchRun(spec)))
        return "proposed a run (awaiting approval)"
    }
}

@MainActor
enum CockpitTools {
    /// The standard safe toolset, bound to the shared stores + active workspace.
    static func standard(
        memory: any MemoryStore,
        history: RunHistoryStore,
        graph: KnowledgeGraphStore,
        workspace: Workspace?
    ) -> [AgentTool] {
        [
            MemorySearchTool(memory: memory),
            MemoryWriteTool(memory: memory, scope: workspace.map { .workspace($0.id) } ?? .global),
            RecentRunsTool(history: history, workspace: workspace),
            RememberFactTool(graph: graph),
        ]
    }

    /// Standard tools plus the gated action tools (proposals routed to `propose`).
    static func withActions(
        memory: any MemoryStore,
        history: RunHistoryStore,
        graph: KnowledgeGraphStore,
        workspace: Workspace?,
        targets: ComputeTargetStore,
        propose: @escaping @MainActor (PendingAction) -> Void
    ) -> [AgentTool] {
        standard(memory: memory, history: history, graph: graph, workspace: workspace) + [
            SwitchComputeTool(targets: targets, propose: propose),
            LaunchRunTool(propose: propose),
        ]
    }
}
