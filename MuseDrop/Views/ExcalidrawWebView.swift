//
//  ExcalidrawWebView.swift
//  MuseDrop
//

import SwiftUI
import WebKit
import AppKit

struct ExcalidrawBridgeMessage: Sendable {
    enum Kind: String, Sendable {
        case ready
        case sceneChanged
        case exportComplete
        case thumbnailComplete
        case error
    }
    
    var kind: Kind
    var sceneJSON: String?
    var format: String?
    var base64: String?
    var errorMessage: String?
}

/// Pins WKWebView to its SwiftUI layout frame (avoids zero-height blank web views).
final class WebViewContainer: NSView {
    let webView: WKWebView
    
    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Forwards script messages weakly so `WKUserContentController` (which retains its
/// handlers strongly) does not create a retain cycle through the Coordinator and
/// leak the WKWebView / its WebContent process.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct ExcalidrawWebView: NSViewRepresentable {
    private static let messageName = "museDrop"

    var onMessage: (ExcalidrawBridgeMessage) -> Void
    var onCoordinatorReady: ((Coordinator) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }
    
    func makeNSView(context: Context) -> WebViewContainer {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // Required for Vite ES-module bundles loaded via file:// in WKWebView.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: Self.messageName)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        
        let container = WebViewContainer(webView: webView)
        
        if let indexURL = PathUtils.excalidrawHostIndexURL(),
           let readAccess = PathUtils.excalidrawHostReadAccessURL() {
            webView.loadFileURL(indexURL, allowingReadAccessTo: readAccess)
        } else {
            DispatchQueue.main.async {
                onMessage(ExcalidrawBridgeMessage(
                    kind: .error,
                    errorMessage: "ExcalidrawHost/index.html not found. Run ./scripts/build-excalidraw-host.sh, then rebuild."
                ))
            }
        }
        
        DispatchQueue.main.async {
            onCoordinatorReady?(context.coordinator)
        }
        return container
    }
    
    func updateNSView(_ nsView: WebViewContainer, context: Context) {}

    static func dismantleNSView(_ nsView: WebViewContainer, coordinator: Coordinator) {
        let webView = nsView.webView
        webView.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        webView.navigationDelegate = nil
        webView.stopLoading()
        coordinator.webView = nil
    }
    
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var webView: WKWebView?
        let onMessage: (ExcalidrawBridgeMessage) -> Void
        
        init(onMessage: @escaping (ExcalidrawBridgeMessage) -> Void) {
            self.onMessage = onMessage
        }
        
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "museDrop",
                  let body = message.body as? [String: Any],
                  let typeRaw = body["type"] as? String,
                  let kind = ExcalidrawBridgeMessage.Kind(rawValue: typeRaw) else {
                return
            }
            
            onMessage(ExcalidrawBridgeMessage(
                kind: kind,
                sceneJSON: body["sceneJSON"] as? String,
                format: body["format"] as? String,
                base64: body["base64"] as? String,
                errorMessage: body["message"] as? String
            ))
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportLoadError(error)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportLoadError(error)
        }
        
        private func reportLoadError(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return
            }
            onMessage(ExcalidrawBridgeMessage(
                kind: .error,
                errorMessage: "Canvas failed to load: \(error.localizedDescription)"
            ))
        }
        
        func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }
        
        func setTheme(theme: String, accentHex: String) {
            let payload: [String: Any] = [
                "theme": theme,
                "accentColor": accentHex,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            let escaped = json
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            evaluate("window.museDropBridge?.setTheme(JSON.parse('\(escaped)'));")
        }
        
        func loadScene(theme: String, accentHex: String, sceneJSON: String?) {
            var payload: [String: Any] = [
                "theme": theme,
                "accentColor": accentHex,
            ]
            if let sceneJSON {
                payload["sceneJSON"] = sceneJSON
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            let escaped = json
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            evaluate("window.museDropBridge?.loadScene(JSON.parse('\(escaped)'));")
        }
        
        func pushElementsJSON(_ json: String) {
            let escaped = json
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            evaluate("window.museDropBridge?.pushElements(JSON.parse('\(escaped)'));")
        }
        
        func requestSave() {
            evaluate("window.museDropBridge?.requestSave();")
        }
        
        func exportPNG() {
            evaluate("window.museDropBridge?.exportPNG();")
        }
        
        func exportJSON() {
            evaluate("window.museDropBridge?.exportJSON();")
        }
        
        func exportThumbnail() {
            evaluate("window.museDropBridge?.exportThumbnail();")
        }
    }
}

extension ExcalidrawWebView {
    static func accentHex(from color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    static func themeName() -> String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    }
}
