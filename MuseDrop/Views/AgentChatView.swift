//
//  AgentChatView.swift
//  MuseDrop
//
//  Phase G.2: the agent panel in the Cockpit. Ask mode — a chat grounded in the
//  workspace's memory (working context) + recent runs, streamed through the user's
//  configured provider via `RoutedLLMClient`. Edit/Agent tool-calling is next.
//

import SwiftUI

struct AgentChatView: View {
    let workspace: Workspace?
    let recentRuns: [Run]

    @StateObject private var agent: CockpitAgent
    @State private var draft = ""
    @State private var mode: Mode = .ask
    private let routeStatus: String
    private let routeAvailable: Bool

    enum Mode: String, CaseIterable, Identifiable { case ask, agent; var id: String { rawValue }
        var label: String { self == .ask ? "Ask" : "Agent" } }

    init(workspace: Workspace?, recentRuns: [Run]) {
        self.workspace = workspace
        self.recentRuns = recentRuns
        let settings = LLMProviderSettings.load()
        self.routeStatus = LLMRouter.shared.statusDescription(settings: settings)
        self.routeAvailable = LLMRouter.shared.resolveRoute(settings: settings) != .unavailable
        _agent = StateObject(wrappedValue: CockpitAgent(
            llm: RoutedLLMClient(settings: settings),
            model: settings.modelId,
            memory: LocalMemoryStore.shared))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SectionRule()
            transcript
            if !agent.pendingActions.isEmpty {
                SectionRule()
                pendingActionsBar
            }
            SectionRule()
            composer
        }
        .frame(minWidth: 280)
    }

    private var pendingActionsBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(agent.pendingActions) { action in
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(.callout.weight(.medium))
                    if !action.detail.isEmpty {
                        Text(action.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack {
                        Spacer()
                        Button("Deny", role: .cancel) { agent.deny(action.id) }
                            .controlSize(.small)
                        Button("Approve") { Task { await agent.approve(action.id) } }
                            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.warning.opacity(0.10)))
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Label("Agent", systemImage: "sparkles").font(.headline)
                Spacer()
                Text(routeStatus).font(.caption2).foregroundStyle(.secondary)
                if !agent.messages.isEmpty {
                    Button { agent.clear() } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Clear conversation")
                }
            }
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .help(mode == .ask ? "Answer questions from memory" : "Use tools to act (search, save, link facts)")
        }
        .padding(Theme.Spacing.md)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if agent.messages.isEmpty {
                        Text(routeAvailable
                             ? "Ask about this workspace — grounded in its runs, notes, and your research."
                             : "Set an AI provider in Settings → AI Providers to use the agent.")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.top, Theme.Spacing.md)
                    }
                    ForEach(agent.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if agent.isThinking {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").font(.caption).foregroundStyle(.secondary) }
                            .id("thinking")
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: agent.messages.count) { _, _ in
                withAnimation { proxy.scrollTo(agent.messages.last?.id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Ask the agent…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .onSubmit(send)
            Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.isThinking)
        }
        .padding(Theme.Spacing.md)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !agent.isThinking else { return }
        draft = ""
        switch mode {
        case .ask:
            Task { await agent.ask(text, workspace: workspace, recentRuns: recentRuns) }
        case .agent:
            let tools = CockpitTools.withActions(
                memory: LocalMemoryStore.shared,
                history: RunHistoryStore.shared,
                graph: KnowledgeGraphStore.shared,
                workspace: workspace,
                targets: ComputeTargetStore.shared,
                propose: { agent.proposeAction($0) })
            Task { await agent.act(text, tools: tools, workspace: workspace) }
        }
    }
}

private struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 24) }
            Text(message.text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(isUser ? Theme.accent.opacity(0.16) : Color(nsColor: .textBackgroundColor).opacity(0.5))
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 24) }
        }
    }
}
