//
//  PodcastTranscript.swift
//  Kekasatori
//
//  The two-host dialogue persisted alongside a generated podcast, with an
//  approximate start time per line (derived from each synthesized segment's
//  audio duration). Stored as a sidecar JSON next to the WAV so the player can
//  show an Apple-Podcasts-style transcript with no data-model change.
//

import Foundation

struct PodcastTranscriptLine: Codable, Identifiable, Hashable {
    var id = UUID()
    var speaker: String
    var text: String
    /// Approximate start time in seconds.
    var start: Double

    private enum CodingKeys: String, CodingKey { case speaker, text, start }
}

struct PodcastTranscript: Codable {
    var lines: [PodcastTranscriptLine]
}

enum PodcastTranscriptStore {
    /// Sidecar path next to the audio (…/podcast-x.transcript.json).
    static func sidecarURL(for audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension("transcript.json")
    }

    static func save(_ transcript: PodcastTranscript, for audioURL: URL) {
        guard !transcript.lines.isEmpty,
              let data = try? JSONEncoder().encode(transcript) else { return }
        try? data.write(to: sidecarURL(for: audioURL))
    }

    static func load(for audioURL: URL) -> PodcastTranscript? {
        let url = sidecarURL(for: audioURL)
        guard let data = try? Data(contentsOf: url),
              let transcript = try? JSONDecoder().decode(PodcastTranscript.self, from: data),
              !transcript.lines.isEmpty else { return nil }
        return transcript
    }
}
