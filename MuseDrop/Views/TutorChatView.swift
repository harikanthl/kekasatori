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
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tutor")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    modelMenu
                    if viewModel.isPreparing {
                        Text("· indexing…")
                    } else if viewModel.hasContext {
                        Text("· grounded in this \(item.isResearchDocument ? "paper" : "transcript")")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
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
                    Text("Add an OpenRouter API key in Settings → AI Providers to use cloud models.")
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(viewModel.activeRouteLabel)
                if viewModel.needsKey {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
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
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
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
                .lineLimit(1...5)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6))
                )
                .onSubmit { viewModel.send() }
                .disabled(!viewModel.providerConfigured)

            if viewModel.isStreaming {
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.danger)
                .help("Stop")
            } else {
                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(viewModel.input.trimmingCharacters(in: .whitespaces).isEmpty || !viewModel.providerConfigured)
            }
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
            Text("…").font(.callout)
        } else if isUser {
            // User input is literal text — render plain so markdown characters
            // they typed aren't reinterpreted.
            Text(message.content).font(.callout)
        } else {
            MarkdownMessageView(text: message.content)
        }
    }
}
