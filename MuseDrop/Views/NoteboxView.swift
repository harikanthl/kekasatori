//
//  NotebookView.swift
//  MuseDrop
//
//  Phase E: the notebook pane. Starts a marimo server in a container and embeds it
//  in a WKWebView. CPU-only locally; the compute dial promotes it to GPU once
//  persistent pods land (Phase D). The live run needs Docker + the marimo image.
//

import SwiftUI
import WebKit

@MainActor
final class NoteboxViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case ready(String)   // URL
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var runtime: ContainerRuntimeStatus?
    @Published var image: String =
        LabEnvironment.presets.first { $0.kind == .interactive }?.baseImage ?? "python:3.12-slim"

    /// `.py` files in the workdir, and which one the server is currently editing.
    @Published private(set) var notebooks: [String] = []
    @Published private(set) var currentNotebook = NoteboxServerService.notebookFile
    /// Bumped on every (re)start so the WebView reloads even when the URL is unchanged
    /// (single-file mode always serves the editor at the same root URL).
    @Published private(set) var reloadToken = 0

    /// Apple Container runs a background daemon you must start before running containers
    /// (Docker/Colima manage their own). These drive the engine controls in the header.
    @Published var engineBusy = false
    @Published private(set) var engineRunning: Bool?   // nil = unknown
    @Published var engineMessage: String?

    var isAppleContainer: Bool { runtime?.engine == .appleContainer }

    private let hostPort = 2718
    private var runner: ProcessRunner?
    private var pollTask: Task<Void, Never>?

    init() { checkRuntime() }

    func checkRuntime() {
        Task { @MainActor [weak self] in self?.runtime = await ContainerRuntime.check() }
    }

    var canStart: Bool {
        guard runtime?.isReady ?? false else { return false }
        switch state { case .idle, .failed: return true; default: return false }
    }

    private func workdir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kekanotebook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() {
        guard let status = runtime, status.isReady, let cli = status.executable else {
            state = .failed("No container engine detected — install one to run notebooks.")
            return
        }
        state = .starting
        refreshNotebooks()
        let args = NoteboxServerService.arguments(image: image, hostPort: hostPort,
                                                  hostWorkdir: workdir().path, notebook: currentNotebook)
        let runner = ProcessRunner()
        self.runner = runner

        // Keep the server process alive in the background; an early exit = failure.
        Task { @MainActor [weak self] in
            // Apple Container needs its daemon up before `run`; idempotent, best-effort.
            if status.engine == .appleContainer {
                let r = await ContainerRuntime.startSystemService(status)
                if r.ok { self?.engineRunning = true }
            }
            // Clear any leftover server first — a daemon-backed container outlives the CLI
            // client, so a prior crash/quit can leave one holding the name and port 2718.
            await Self.tearDownContainer(cli: cli)
            do {
                for try await _ in runner.runWithProgress(executable: cli, arguments: args) {}
                if case .ready = self?.state { self?.state = .idle }   // server exited
            } catch is CancellationError {
                // stopped by us
            } catch {
                if case .ready = self?.state {} else { self?.state = .failed(error.localizedDescription) }
            }
        }

        pollTask = Task { @MainActor [weak self] in await self?.pollReady() }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        runner?.cancel(); runner = nil
        // Cancelling the `run` client doesn't stop the daemon-backed container; stop it by name.
        if let cli = runtime?.executable { Task { await Self.tearDownContainer(cli: cli) } }
        state = .idle
    }

    /// Start the Apple Container daemon (`container system start`).
    func startEngine() {
        guard let status = runtime else { return }
        engineBusy = true; engineMessage = nil
        Task { @MainActor [weak self] in
            let r = await ContainerRuntime.startSystemService(status)
            self?.engineBusy = false
            if r.ok { self?.engineRunning = true }
            self?.engineMessage = r.message.isEmpty ? nil : r.message
        }
    }

    /// Stop the Apple Container daemon (`container system stop`). Tears down any running
    /// notebook first so we don't orphan a container the dead daemon can't clean up.
    func stopEngine() {
        guard let status = runtime else { return }
        stop()
        engineBusy = true; engineMessage = nil
        Task { @MainActor [weak self] in
            let r = await ContainerRuntime.stopSystemService(status)
            self?.engineBusy = false
            if r.ok { self?.engineRunning = false }
            self?.engineMessage = r.message.isEmpty ? nil : r.message
        }
    }

    /// Best-effort `container stop kekanotebox` — frees the name + port 2718. Ignores
    /// failures (nothing running / unknown name).
    private static func tearDownContainer(cli: URL) async {
        let runner = ProcessRunner()
        do {
            for try await _ in runner.runWithProgress(executable: cli, arguments: NoteboxServerService.stopArguments()) {}
        } catch {}
    }

    /// Create a fresh `notebook-N.py`, switch to it, and restart the server on it.
    func newNotebook() {
        let name = freshNotebookName()
        FileManager.default.createFile(atPath: workdir().appendingPathComponent(name).path, contents: Data())
        currentNotebook = name
        refreshNotebooks()
        restart()
    }

    /// Switch the editor to an existing notebook (restarts the single-file server on it).
    func open(_ name: String) {
        guard name != currentNotebook else { return }
        currentNotebook = name
        restart()
    }

    private func restart() { stop(); start() }

    private func refreshNotebooks() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: workdir().path)) ?? []
        notebooks = files.filter { $0.hasSuffix(".py") }.sorted()
    }

    private func freshNotebookName() -> String {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: workdir().path)) ?? [])
        if !existing.contains(NoteboxServerService.notebookFile) { return NoteboxServerService.notebookFile }
        var n = 2
        while existing.contains("notebook-\(n).py") { n += 1 }
        return "notebook-\(n).py"
    }

    private func pollReady() async {
        guard let url = URL(string: NoteboxServerService.healthURL(hostPort: hostPort)) else { return }
        for _ in 0..<90 {                      // ~90s for first-run pip install
            if Task.isCancelled { return }
            if case .failed = state { return }
            if await Self.isUp(url) {
                reloadToken += 1
                state = .ready(NoteboxServerService.url(hostPort: hostPort))
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if case .ready = state {} else { state = .failed("The notebook server didn’t come up in time.") }
    }

    private static func isUp(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: request)) != nil
    }
}

struct NoteboxView: View {
    /// Forwarded to the embedded web view so its hidden NSView doesn't leak the I-beam
    /// cursor onto other tabs when Notebox isn't selected.
    var isActive: Bool = true
    @StateObject private var model = NoteboxViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            SectionRule()
            if let msg = model.engineMessage {
                Text(msg)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            content
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            ScreenHeader(title: "Notebox",
                         subtitle: "A reactive marimo notebook in a container — HF/torch ready.",
                         systemImage: "book.pages")
            Spacer()
            if model.isAppleContainer { engineControls }
            switch model.state {
            case .ready:
                HStack(spacing: Theme.Spacing.sm) {
                    if model.notebooks.count > 1 {
                        Menu {
                            ForEach(model.notebooks, id: \.self) { nb in
                                Button { model.open(nb) } label: {
                                    Label(nb, systemImage: nb == model.currentNotebook ? "checkmark" : "doc.text")
                                }
                            }
                        } label: {
                            Label(model.currentNotebook, systemImage: "book.pages")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    Button { model.newNotebook() } label: { Label("New", systemImage: "plus") }
                    Button(role: .cancel) { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                }
            case .starting:
                ProgressView().controlSize(.small)
            default:
                Button { model.start() } label: { Label("Start Notebox", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(!model.canStart)
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// Apple Container's daemon is manual (unlike Docker/Colima). Surface start/stop here
    /// so the engine can be brought up before launching, or shut down to free resources.
    @ViewBuilder
    private var engineControls: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if model.engineBusy { ProgressView().controlSize(.small) }
            Button { model.startEngine() } label: { Label("Start Engine", systemImage: "power") }
                .disabled(model.engineBusy || model.engineRunning == true)
            Button { model.stopEngine() } label: { Label("Stop Engine", systemImage: "stop.circle") }
                .disabled(model.engineBusy || model.engineRunning == false)
        }
        .help("Apple Container runs a background service — start it before launching a notebook, stop it to free resources.")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .ready(let url):
            NoteboxWebView(urlString: url, reloadToken: model.reloadToken, isActive: isActive)
        case .starting:
            VStack(spacing: Theme.Spacing.md) {
                PlayfulLoader(size: 260)
                RetroThinkingTicker(messages: ThinkingLines.notebook)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn’t start", message: message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle:
            EmptyStateView(systemImage: "book.pages",
                           title: model.canStart ? "Ready when you are" : "Needs a container engine",
                           message: model.canStart
                               ? "Start a reactive marimo notebook in a sandboxed container."
                               : "Install Docker or Apple Container to run notebooks.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NoteboxWebView: NSViewRepresentable {
    let urlString: String
    let reloadToken: Int
    var isActive: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.uiDelegate = context.coordinator
        webView.isHidden = !isActive
        context.coordinator.token = reloadToken
        load(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.isHidden = !isActive   // stop tracking/cursor when tab inactive
        // A new token means the server restarted (e.g. switched notebook) — force a
        // reload even though the root URL is unchanged. Otherwise reload only on URL change.
        if context.coordinator.token != reloadToken {
            context.coordinator.token = reloadToken
            load(webView)
        } else if webView.url?.absoluteString != urlString {
            load(webView)
        }
    }

    private func load(_ webView: WKWebView) {
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    /// Without a WKUIDelegate, WKWebView silently drops `window.open` / `target="_blank"`
    /// navigations — so any marimo link that opens a new tab does nothing. Loading the
    /// request in-place keeps the embedded single-window experience working.
    final class Coordinator: NSObject, WKUIDelegate {
        var token = -1

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame?.isMainFrame != true {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
