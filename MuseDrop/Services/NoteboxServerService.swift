//
//  NoteboxServerService.swift
//  MuseDrop
//
//  Phase E: run a notebook server (marimo) inside a container and embed it in a
//  WebView. marimo is reactive, stores notebooks as pure .py, and serves over a
//  configurable host/port — so it runs headless in a container and embeds via a
//  localhost WebView (docs/cockpit-architecture.md Phase E). Command + URL
//  building are pure (tested); the live container run is driven by ProcessRunner
//  (needs Docker + the marimo image, so unverified end-to-end here).
//

import Foundation

enum NoteboxServerService {
    /// marimo's default server port, inside the container.
    static let containerPort = 2718

    /// The notebook file marimo opens directly, relative to /work. Editing a specific
    /// file (rather than the /work directory) drops the user straight into the reactive
    /// editor instead of the home dashboard — whose "New notebook" opens a second browser
    /// tab that a bare WKWebView silently swallows (no WKUIDelegate).
    static let notebookFile = "notebook.py"

    /// Stable container name so we can explicitly tear the server down. Daemon-backed
    /// runtimes (Apple `container`, Docker) keep the container alive after the `run` CLI
    /// client is killed, so cancelling the process isn't enough — a leftover server would
    /// hold port 2718 and shadow the next launch with its stale (dashboard) page.
    static let containerName = "kekanotebox"

    /// `run --rm --name <name> -p <hostPort>:2718 -v <workdir>:/work -w /work <image> sh -c "<install + serve>"`.
    /// The slim image gets marimo installed on first start; a prebuilt "lab" image
    /// makes that a no-op. Auth is disabled — the server is bound to a published
    /// localhost port on the user's own machine, embedded only in our WebView.
    ///
    /// We `marimo edit /work/<file>` (creating it if absent) so the WebView lands in the
    /// editor, not the dashboard. A `+ New notebook` belongs in our own SwiftUI chrome.
    static func arguments(image: String, hostPort: Int, hostWorkdir: String,
                          notebook: String = notebookFile) -> [String] {
        // `marimo[sql]` pulls in DuckDB so SQL cells work out of the box; polars is marimo's
        // preferred (faster) result type, pyarrow adds Parquet, altair powers reactive charts.
        // Echo friendly milestones (streamed to the UI) so first-run shows what's installing.
        let serve = """
        echo '☕️ Brewing your notebook…'; \
        echo '📦 marimo + SQL engine (duckdb)…'; pip install -q "marimo[sql]" duckdb 2>/dev/null; \
        echo '📊 dataframes — pandas, polars, pyarrow…'; pip install -q pandas polars pyarrow 2>/dev/null; \
        echo '📈 charts — numpy, matplotlib, altair…'; pip install -q numpy matplotlib altair 2>/dev/null; \
        echo '✅ All set — launching marimo, hold tight…'; \
        touch /work/\(notebook); \
        marimo edit --headless --host 0.0.0.0 --port \(containerPort) --no-token /work/\(notebook)
        """
        return ["run", "--rm", "--name", containerName,
                "-p", "\(hostPort):\(containerPort)",
                "-v", "\(hostWorkdir):/work",
                "-w", "/work",
                image, "sh", "-c", serve]
    }

    /// Args to force-stop the named server container. `--rm` removes it on stop, freeing
    /// both the name and port. Best-effort: ignore failure (nothing running / unknown name).
    static func stopArguments() -> [String] { ["stop", containerName] }

    /// The localhost URL the WebView loads once the server is up.
    static func url(hostPort: Int) -> String {
        "http://127.0.0.1:\(hostPort)"
    }

    /// A readiness probe URL (same as the page; a 200 means marimo is serving).
    static func healthURL(hostPort: Int) -> String { url(hostPort: hostPort) }
}
