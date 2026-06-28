//
//  MonacoEditorView.swift
//  MuseDrop
//
//  The Monaco (VS Code) editor in a WKWebView, mirroring the ExcalidrawWebView
//  pattern. Monaco is **vendored offline** (Resources/MonacoHost/vs) and loaded
//  via file:// — no CDN, no network, no flash. Two-way bound to `text`, with
//  language + light/dark driven from Swift. Initial content is injected once the
//  host page posts `ready`.
//

import SwiftUI
import WebKit
import AppKit

struct MonacoEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: String        // Monaco language id: "python", "shell"
    var dark: Bool

    private static let messageName = "monaco"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WebViewContainer {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // Let Monaco's AMD loader fetch vs/* modules from the file:// host page.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.userContentController.add(MonacoWeakHandler(context.coordinator), name: Self.messageName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Non-opaque + an editor-coloured underlay → no white flash on load.
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = dark ? NSColor(white: 0.118, alpha: 1) : .white
        context.coordinator.webView = webView

        let container = WebViewContainer(webView: webView)
        if let indexURL = PathUtils.monacoHostIndexURL(),
           let readAccess = PathUtils.monacoHostReadAccessURL() {
            webView.loadFileURL(indexURL, allowingReadAccessTo: readAccess)
        }
        return container
    }

    func updateNSView(_ nsView: WebViewContainer, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self                 // keep the binding fresh
        guard coordinator.ready else { return }   // initial push happens on `ready`
        if text != coordinator.lastReportedText {
            coordinator.lastReportedText = text
            coordinator.setCode(text)
        }
        if language != coordinator.currentLanguage {
            coordinator.currentLanguage = language
            coordinator.setLanguage(language)
        }
        if dark != coordinator.currentDark {
            coordinator.currentDark = dark
            coordinator.setTheme(dark: dark)
        }
    }

    static func dismantleNSView(_ nsView: WebViewContainer, coordinator: Coordinator) {
        nsView.webView.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        nsView.webView.navigationDelegate = nil
        nsView.webView.stopLoading()
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MonacoEditorView
        weak var webView: WKWebView?
        var ready = false
        var lastReportedText: String
        var currentLanguage: String
        var currentDark: Bool

        init(_ parent: MonacoEditorView) {
            self.parent = parent
            self.lastReportedText = parent.text
            self.currentLanguage = parent.language
            self.currentDark = parent.dark
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }

            // Host page is up — push the initial code / language / theme.
            if (body["type"] as? String) == "ready" {
                ready = true
                lastReportedText = parent.text
                currentLanguage = parent.language
                currentDark = parent.dark
                setCode(parent.text)
                setLanguage(parent.language)
                setTheme(dark: parent.dark)
                return
            }
            if let code = body["code"] as? String {
                lastReportedText = code
                parent.text = code
            }
        }

        func setCode(_ code: String) { evaluate("window.__setCode(\(Self.jsString(code)));") }
        func setLanguage(_ language: String) { evaluate("window.__setLanguage(\(Self.jsString(language)));") }
        func setTheme(dark: Bool) { evaluate("window.__setTheme(\(dark ? "true" : "false"));") }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        /// JSON-encode a Swift string into a safe JS string literal.
        static func jsString(_ value: String) -> String {
            (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "\"\""
        }
    }
}

/// Weak forwarder so WKUserContentController doesn't retain the Coordinator.
private final class MonacoWeakHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}
