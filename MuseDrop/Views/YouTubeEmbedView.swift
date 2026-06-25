//
//  YouTubeEmbedView.swift
//  Kekasatori
//
//  Plays YouTube videos via the official IFrame embed (youtube-nocookie) for
//  full quality. Used for YouTube *stream* playback, where yt-dlp can only
//  resolve ~360p as a single AVPlayer URL. Local files and non-YouTube sources
//  continue to use AVPlayer.
//

import SwiftUI
import WebKit

struct YouTubeEmbedView: NSViewRepresentable {
    let videoID: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Allow the embed to autoplay without a click.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        // Avoid a white flash before the (black) page paints.
        webView.setValue(false, forKey: "drawsBackground")
        webView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        webView.setContentHuggingPriority(.defaultLow, for: .vertical)

        context.coordinator.currentID = videoID
        load(videoID, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentID != videoID else { return }
        context.coordinator.currentID = videoID
        load(videoID, into: webView)
    }

    /// Stop playback when the view is removed (e.g. the player window closes) —
    /// otherwise the embedded player keeps playing audio in the background.
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading()
        nsView.loadHTMLString("<html><body style=\"background:#000\"></body></html>", baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var currentID: String?
    }

    private func load(_ id: String, into webView: WKWebView) {
        webView.loadHTMLString(
            Self.html(for: id),
            baseURL: URL(string: "https://www.youtube-nocookie.com")
        )
    }

    static func html(for id: String) -> String {
        // Escape is unnecessary: video IDs are [A-Za-z0-9_-].
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          html, body { margin: 0; padding: 0; height: 100%; width: 100%; background: #000; overflow: hidden; }
          .wrap { position: absolute; inset: 0; }
          iframe { width: 100%; height: 100%; border: 0; display: block; }
        </style>
        </head>
        <body>
          <div class="wrap">
            <iframe
              src="https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&playsinline=1&rel=0&modestbranding=1"
              allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
              allowfullscreen></iframe>
          </div>
        </body>
        </html>
        """
    }
}
