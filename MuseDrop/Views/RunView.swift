//
//  RunView.swift
//  Kekasatori
//
//  Run pillar (Phase 3a): benchmark any model — a cloud BYOK column from Compare
//  or a detected host-native server — by running lm-eval / inspect-ai inside a
//  container. The container engine + harness/image live in the image; the host
//  only needs a runtime. Streams the log live and scrapes metrics at the end.
//  The same image will later run on a remote GPU (Phase 3b), so "the same thing"
//  runs locally and remotely.
//

import SwiftUI

struct RunView: View {
    @StateObject private var model = RunViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ScreenHeader(
                        title: "Run",
                        subtitle: "Benchmark any model — local or cloud — in a container.",
                        systemImage: "chart.bar.xaxis"
                    )
                    SectionRule()
                }
                .padding(.top, Theme.Spacing.xl)

                engineSection
                configCard
                commandCard
                if !model.metrics.isEmpty { metricsCard }
                consoleCard

                Spacer(minLength: Theme.Spacing.xxl)
            }
            .screenColumn()
            .padding(.bottom, Theme.Spacing.xxl)
        }
    }

    // MARK: - Engine status

    @ViewBuilder
    private var engineSection: some View {
        if let runtime = model.runtime {
            if runtime.isReady {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "shippingbox.fill").foregroundStyle(Theme.success)
                    Text(runtime.statusMessage).font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    if model.canStartEngine {
                        Button("Start engine") { model.startEngine() }
                            .controlSize(.small)
                    }
                    Button("Re-check") { model.checkRuntime() }
                        .controlSize(.small)
                }
                .padding(Theme.Spacing.md)
                .cardSurface(radius: Theme.Radius.md)
            } else {
                runtimeBanner(runtime)
            }
        } else {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Detecting container engine…").foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.md)
            .cardSurface(radius: Theme.Radius.md)
        }
    }

    private func runtimeBanner(_ runtime: ContainerRuntimeStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text(runtime.statusMessage)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if model.canInstallAppleContainer {
                    Button { model.installAppleContainer() } label: {
                        if model.installing {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading…") }
                        } else {
                            Label("Install Apple Container", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    .disabled(model.installing)
                }
                Button("Re-check") { model.checkRuntime() }
                    .controlSize(.small)
            }
            Text(runtime.installHint)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(Theme.Spacing.md)
        .cardSurface(radius: Theme.Radius.md)
    }

    // MARK: - Config

    private var configCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionLabel("Benchmark", systemImage: "slider.horizontal.3")

            // Model
            LabeledRow("Model") {
                HStack(spacing: Theme.Spacing.sm) {
                    Menu {
                        if !model.cloudModels.isEmpty {
                            Section("Cloud (Compare columns)") {
                                ForEach(model.cloudModels) { p in
                                    Button(p.label) { model.selectModel(p) }
                                }
                            }
                        }
                        Section("Local servers") {
                            if model.localModels.isEmpty {
                                Text("None detected").foregroundStyle(.secondary)
                            }
                            ForEach(model.localModels) { p in
                                Button(p.label) { model.selectModel(p) }
                            }
                        }
                    } label: {
                        HStack {
                            Text(model.selectedModel?.label ?? "Choose a model")
                                .foregroundStyle(model.selectedModel == nil ? .secondary : .primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .floatingChrome(radius: Theme.Radius.sm)

                    Button { model.refreshLocalModels() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Re-scan for local servers (Ollama, LM Studio, llama.cpp)")
                    .controlSize(.small)
                }
            }

            // Harness
            LabeledRow("Harness") {
                Picker("Harness", selection: $model.config.harness) {
                    ForEach(EvalConfig.Harness.allCases) { h in
                        Text(h.displayName).tag(h)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // Task
            LabeledRow("Task") {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("e.g. gsm8k", text: $model.config.task)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 6)
                        .floatingChrome(radius: Theme.Radius.sm)
                        .frame(maxWidth: 260)
                    Menu("Common") {
                        ForEach(EvalConfig.commonTasks, id: \.self) { t in
                            Button(t) { model.config.task = t }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            // Limit
            LabeledRow("Limit") {
                Stepper(value: $model.config.limit, in: 1...500) {
                    Text("\(model.config.limit) example\(model.config.limit == 1 ? "" : "s")")
                        .monospacedDigit()
                }
                .fixedSize()
            }

            // Image (advanced)
            DisclosureGroup("Advanced") {
                LabeledRow("Image") {
                    TextField("container image", text: $model.config.image)
                        .textFieldStyle(.plain)
                        .font(.caption.monospaced())
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 6)
                        .floatingChrome(radius: Theme.Radius.sm)
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .font(.caption.weight(.medium))
            .tint(Theme.accent)

            runBar
        }
        .padding(Theme.Spacing.lg)
        .cardSurface(radius: Theme.Radius.md)
    }

    private var runBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            if model.isRunning {
                Button(role: .cancel) { model.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .controlSize(.large)
                ProgressView().controlSize(.small)
            } else {
                Button { model.run() } label: {
                    Label("Run benchmark", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(!model.canRun)
            }
            if let note = model.statusNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Command preview

    @ViewBuilder
    private var commandCard: some View {
        if !model.previewCommand.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionLabel("Command", systemImage: "terminal")
                Text(model.previewCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.fieldFill))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            }
        }
    }

    // MARK: - Metrics

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("Results", systemImage: "checkmark.seal")
            ChipFlow(spacing: Theme.Spacing.sm) {
                ForEach(model.metrics) { metric in
                    metricChip(metric)
                }
            }
            Text("Scraped from the log — advisory. The full log below is the source of truth.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.lg)
        .cardSurface(radius: Theme.Radius.md)
    }

    private func metricChip(_ metric: EvalMetric) -> some View {
        let formatted = metric.value.formatted(.number.precision(.fractionLength(0...4)))
        return HStack(spacing: 6) {
            Text(metric.label).foregroundStyle(.secondary)
            Text(formatted)
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
        }
        .font(.caption)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.accent.opacity(0.10)))
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.25)))
    }

    // MARK: - Console

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                sectionLabel("Log", systemImage: "text.alignleft")
                if model.isRunning { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            .padding(.bottom, Theme.Spacing.xs)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.log.isEmpty ? "Run a benchmark to stream container output here." : model.log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(model.log.isEmpty ? .tertiary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.sm)
                    Color.clear.frame(height: 1).id(Self.logBottom)
                }
                .frame(minHeight: 220, maxHeight: 420)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                .onChange(of: model.log) { _, _ in
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(Self.logBottom, anchor: .bottom) }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .cardSurface(radius: Theme.Radius.md)
    }

    private static let logBottom = "log-bottom"

    // MARK: - Helpers

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

/// A leading label + trailing control row used across the config card.
private struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}
