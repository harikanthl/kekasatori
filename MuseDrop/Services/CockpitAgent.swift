//
//  CockpitAgent.swift
//  MuseDrop
//
//  Phase G (core): the in-cockpit assistant, Ask mode. Grounds each turn in the
//  agentic memory (working context) + the active workspace + recent runs, then
//  answers via the provider-agnostic `LLMClient`, and writes the exchange back to
//  memory so the agent gets more useful over time. Built against the `LLMClient`
//  protocol + an injectable `MemoryStore`, so prompt assembly and the turn loop are
//  unit-tested with a fake. Edit/Agent modes (tool-calling over the cockpit's
//  objects, via MCP) + the live LLMRouter wiring + chat UI are G.2.
//

import Foundation

struct AgentMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    var role: LLMRole
    var text: String

    init(id: UUID = UUID(), role: LLMRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Pure prompt assembly — testable without a model.
enum AgentPrompt {
    static let system = """
    You are the research cockpit's assistant. Answer concisely using the provided \
    memory and workspace context, and refer to prior runs or papers when relevant. \
    If the context doesn't cover the question, say what's missing rather than guessing.
    """

    static func build(
        question: String,
        workingContext: String,
        workspace: Workspace?,
        recentRuns: [Run]
    ) -> [LLMMessage] {
        var context = ""
        if let workspace { context += "Workspace: \(workspace.title) (\(workspace.source.label))\n" }
        if !workingContext.isEmpty { context += workingContext + "\n" }
        if !recentRuns.isEmpty {
            let lines = recentRuns.prefix(5).map { "- \($0.kind.rawValue): \(statusWord($0.status))" }
            context += "Recent runs:\n" + lines.joined(separator: "\n") + "\n"
        }

        var messages = [LLMMessage(.system, system)]
        if !context.isEmpty { messages.append(LLMMessage(.system, "Context:\n" + context)) }
        messages.append(LLMMessage(.user, question))
        return messages
    }

    /// System prompt for the tool-calling (Agent) loop.
    @MainActor
    static func toolSystem(tools: [AgentTool]) -> String {
        let list = tools.map { "- \($0.spec)" }.joined(separator: "\n")
        return """
        You are the research cockpit's operator. You can call tools to read and \
        record information. To call a tool, reply with ONE line:
        TOOL <name> {<json args>}
        After you receive TOOL_RESULT, either call another tool or finish with:
        ANSWER: <your answer>
        Available tools:
        \(list)
        """
    }

    /// Strip an `ANSWER:` prefix if present.
    static func finalAnswer(_ text: String) -> String {
        if let range = text.range(of: "ANSWER:") {
            return text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func statusWord(_ status: RunStatus) -> String {
        switch status {
        case .succeeded: return "succeeded"
        case .failed(let why): return "failed (\(why))"
        case .canceled: return "canceled"
        case .running: return "running"
        case .queued: return "queued"
        case .provisioning: return "provisioning"
        }
    }
}

@MainActor
final class CockpitAgent: ObservableObject {
    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var isThinking = false
    @Published private(set) var lastError: String?
    /// Side-effecting actions the agent proposed, awaiting human approval (G.4).
    @Published private(set) var pendingActions: [PendingAction] = []

    private let llm: LLMClient
    private let model: String
    private let memory: any MemoryStore

    /// Executors for approved actions — injectable so the approval gate is tested
    /// without touching real compute/Docker. Defaults wire to the shared stores.
    var computeSelector: @MainActor (UUID) -> Void = { ComputeTargetStore.shared.select($0) }
    var runDispatcher: @MainActor (CodeRunSpec) async -> String = CockpitAgent.defaultRunDispatcher

    init(llm: LLMClient, model: String, memory: any MemoryStore) {
        self.llm = llm
        self.model = model
        self.memory = memory
    }

    // MARK: Approval gate

    /// Called by gated tools to queue an action for approval.
    func proposeAction(_ action: PendingAction) {
        pendingActions.append(action)
        messages.append(AgentMessage(role: .assistant, text: "⏳ Proposed: \(action.title) — needs your approval."))
    }

    func approve(_ id: UUID) async {
        guard let action = pendingActions.first(where: { $0.id == id }) else { return }
        pendingActions.removeAll { $0.id == id }
        switch action.kind {
        case .switchCompute(let targetID):
            computeSelector(targetID)
            messages.append(AgentMessage(role: .assistant, text: "✅ \(action.title)"))
        case .launchRun(let spec):
            messages.append(AgentMessage(role: .assistant, text: "▶️ \(action.title)…"))
            let result = await runDispatcher(spec)
            messages.append(AgentMessage(role: .assistant, text: result))
            memory.remember(RawObservation(text: "Agent ran code → \(result)",
                                           kind: .episodic, source: .agentStep, scope: .global))
        }
    }

    func deny(_ id: UUID) {
        guard let action = pendingActions.first(where: { $0.id == id }) else { return }
        pendingActions.removeAll { $0.id == id }
        messages.append(AgentMessage(role: .assistant, text: "❌ Denied: \(action.title)"))
    }

    /// Real dispatcher: run the spec on the currently-selected compute target and
    /// summarise. Needs a container engine; reuses the whole ComputeBackend stack.
    static func defaultRunDispatcher(_ spec: CodeRunSpec) async -> String {
        let status = await ContainerRuntime.check()
        let backend: ComputeBackend
        switch ComputeTargetStore.shared.makeBackend(runtime: status) {
        case .failure(let error): return error.message
        case .success(let b): backend = b
        }
        var run = Run(kind: .agentStep)
        do {
            for try await event in backend.launch(.code(spec, kind: .agentStep)) { run.apply(event) }
        } catch {
            run.apply(.status(.failed(error.localizedDescription)))
        }
        RunHistoryStore.shared.record(run)
        let tail = run.log.split(separator: "\n").suffix(3).joined(separator: "\n")
        return "Run \(AgentPrompt.statusWord(run.status)).\n\(tail)"
    }

    /// Ask a question grounded in memory + the active workspace. Records the
    /// exchange as an episodic memory scoped to the workspace.
    func ask(_ question: String, workspace: Workspace? = nil, recentRuns: [Run] = []) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }

        messages.append(AgentMessage(role: .user, text: q))
        isThinking = true
        lastError = nil

        let workingContext = memory.workingContext(for: MemoryQuery(text: q), tokenBudget: 800)
        let prompt = AgentPrompt.build(question: q, workingContext: workingContext,
                                       workspace: workspace, recentRuns: recentRuns)

        do {
            let answer = try await llm.complete(messages: prompt, model: model)
            messages.append(AgentMessage(role: .assistant, text: answer))
            let scope: MemoryScope = workspace.map { .workspace($0.id) } ?? .global
            memory.remember(RawObservation(text: "Q: \(q)\nA: \(answer)",
                                           kind: .episodic, source: .chat, scope: scope))
        } catch {
            lastError = error.localizedDescription
            messages.append(AgentMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
        }
        isThinking = false
    }

    /// Agent mode: pursue a goal by calling tools in a ReAct loop, then answer.
    /// Each tool step is surfaced as a message so the work is visible. Records the
    /// goal + result to memory.
    func act(_ goal: String, tools: [AgentTool], workspace: Workspace? = nil, maxSteps: Int = 6) async {
        let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.isEmpty, !isThinking else { return }

        messages.append(AgentMessage(role: .user, text: g))
        isThinking = true
        lastError = nil

        let registry = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var convo: [LLMMessage] = [LLMMessage(.system, AgentPrompt.toolSystem(tools: tools))]
        let workingContext = memory.workingContext(for: MemoryQuery(text: g), tokenBudget: 600)
        if !workingContext.isEmpty { convo.append(LLMMessage(.system, "Context:\n" + workingContext)) }
        convo.append(LLMMessage(.user, g))

        do {
            for _ in 0..<maxSteps {
                let text = try await llm.complete(messages: convo, model: model)
                if let call = ToolCall.parse(text), let tool = registry[call.name] {
                    let result = await tool.run(call.args)
                    messages.append(AgentMessage(role: .assistant, text: "🔧 \(call.name) → \(result)"))
                    convo.append(LLMMessage(.assistant, text))
                    convo.append(LLMMessage(.system, "TOOL_RESULT \(call.name): \(result)"))
                    continue
                }
                let answer = AgentPrompt.finalAnswer(text)
                messages.append(AgentMessage(role: .assistant, text: answer))
                let scope: MemoryScope = workspace.map { .workspace($0.id) } ?? .global
                memory.remember(RawObservation(text: "Goal: \(g)\nResult: \(answer)",
                                               kind: .episodic, source: .agentStep, scope: scope))
                isThinking = false
                return
            }
            messages.append(AgentMessage(role: .assistant, text: "(stopped after \(maxSteps) tool steps)"))
        } catch {
            lastError = error.localizedDescription
            messages.append(AgentMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
        }
        isThinking = false
    }

    func clear() { messages.removeAll(); lastError = nil }
}

/// Live `LLMClient` that routes through the app's configured provider (on-device
/// or cloud BYOK) via `LLMRouter`. The `model` argument is ignored — the route is
/// decided by `settings`. This is the production agent's backend.
struct RoutedLLMClient: LLMClient {
    let settings: LLMProviderSettings

    func stream(messages: [LLMMessage], model: String) -> AsyncThrowingStream<String, Error> {
        let settings = self.settings
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in await LLMRouter.shared.stream(messages: messages, settings: settings) {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
