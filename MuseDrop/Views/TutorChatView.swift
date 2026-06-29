//
//  TutorChatView.swift
//  MuseDrop
//
//  BYOK / RAG study tutor chat. Lives as the first tab in the study panel.
//

import SwiftUI

struct TutorChatView: View {
    let item: DownloadItem
    @StateObject private var viewModel: TutorChatViewModel

    init(item: DownloadItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: TutorChatViewModel(item: item))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !viewModel.providerConfigured {
                notConfiguredState
            } else if viewModel.messages.isEmpty {
                emptyState
            } else {
                messageList
            }

            Divider()
            inputBar
        }
        .onAppear { viewModel.onAppear() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Logo tile
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Tutor").font(.subheadline.weight(.semibold))
                groundingBadge
            }

            Spacer(minLength: Theme.Spacing.sm)

            // Model selector as a distinct chip on the right.
            modelMenu

            if !viewModel.messages.isEmpty {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear conversation")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    /// Small status pill under the title: indexing, grounded, or nothing.
    @ViewBuilder
    private var groundingBadge: some View {
        if viewModel.isPreparing {
            Label("Indexing…", systemImage: "hourglass")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if viewModel.hasContext {
            Label("Grounded in this \(item.isResearchDocument ? "paper" : "transcript")",
                  systemImage: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var modelMenu: some View {
        Menu {
            if viewModel.onDeviceAvailable {
                Button {
                    viewModel.selectOnDevice()
                } label: {
                    Label("Apple Intelligence (on-device)",
                          systemImage: viewModel.isOnDeviceSelected ? "checkmark" : "cpu")
                }
            }

            Section("Cloud models (BYOK)") {
                ForEach(viewModel.cloudModelOptions, id: \.id) { option in
                    Button {
                        viewModel.selectCloudModel(option.id)
                    } label: {
                        if viewModel.isCloudModelSelected(option.id) {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }

            if viewModel.needsKey {
                Section {
                    Text("Add an API key in Settings → AI Providers to use cloud models.")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isOnDeviceSelected ? "cpu" : "cloud")
                    .font(.system(size: 9, weight: .semibold))
                Text(viewModel.activeRouteLabel)
                    .lineLimit(1)
                if viewModel.needsKey {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(viewModel.needsKey
              ? "A cloud model is selected but no API key is configured."
              : "Switch the tutor's AI model")
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(viewModel.messages) { message in
                        TutorMessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                // Non-animated follow during streaming — a per-token animation
                // fights the text growth and reads as jumpy.
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                systemImage: "bubble.left.and.bubble.right",
                title: "Ask the tutor",
                message: viewModel.hasContext
                    ? "Ask anything about this \(item.isResearchDocument ? "paper" : "lecture") — answers are grounded in its content."
                    : "Generate a transcript or import a paper to ground answers in the source."
            )
            suggestionChips
        }
    }

    private var suggestionChips: some View {
        let prompts = ["Summarize the key ideas", "Explain the main method simply", "What are the limitations?"]
        return VStack(spacing: Theme.Spacing.sm) {
            ForEach(prompts, id: \.self) { prompt in
                Button {
                    viewModel.input = prompt
                    viewModel.send()
                } label: {
                    Text(prompt)
                        .font(.callout)
                        .frame(maxWidth: 320)
                        .padding(.vertical, Theme.Spacing.sm)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isStreaming)
            }
        }
    }

    private var notConfiguredState: some View {
        VStack(spacing: Theme.Spacing.md) {
            EmptyStateView(
                systemImage: "key.horizontal",
                title: "No AI provider configured",
                message: "Add an API key (OpenRouter or custom) in Settings → AI Providers, or enable Apple Intelligence on macOS 26."
            )
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
            TextField("Ask about this \(item.isResearchDocument ? "paper" : "lecture")…", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)                      // match the reply text
                .lineLimit(1...6)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .frame(minHeight: 38)                // comfortable, not a thin line
                .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6))
                )
                .onSubmit { viewModel.send() }
                .disabled(!viewModel.providerConfigured)

            Button {
                viewModel.isStreaming ? viewModel.stop() : viewModel.send()
            } label: {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .frame(width: 38, height: 38)    // ≥ HIG hit target, aligned to field height
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isStreaming ? Theme.danger : Theme.accent)
            .disabled(!viewModel.isStreaming
                      && (viewModel.input.trimmingCharacters(in: .whitespaces).isEmpty || !viewModel.providerConfigured))
            .help(viewModel.isStreaming ? "Stop" : "Send")
        }
        .padding(Theme.Spacing.md)
    }
}

private struct TutorMessageBubble: View {
    let message: TutorMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            bubbleContent
                .foregroundStyle(isUser ? Color.white : .primary)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(isUser ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(isUser ? AnyShapeStyle(.clear) : AnyShapeStyle(.separator.opacity(0.5)))
                )
                .frame(maxWidth: 460, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.content.isEmpty {
            // Waiting for the first token — show a lively thinking ticker.
            RetroThinkingTicker(messages: ThinkingLines.tutor)
        } else if isUser {
            // User input is literal text — render plain so markdown characters
            // they typed aren't reinterpreted.
            Text(message.content).font(.callout)
        } else {
            MarkdownMessageView(text: message.content)
        }
    }
}
