//
//  GeminiPodcastService.swift
//  Kekasatori
//
//  Turns source text (selected paper pages) into a two-host "podcast" audio
//  asset using Google's Gemini API: one call writes a conversational script,
//  a second renders it with multi-speaker TTS. BYOK — the key lives only in the
//  Keychain. Audio comes back as raw PCM (24 kHz / 16-bit / mono); we wrap it in
//  a WAV container and save it to the Library audio directory.
//

import Foundation

@MainActor
final class GeminiPodcastService {
    static let shared = GeminiPodcastService()

    // Two hosts; the labels must match the speaker configs in the TTS request.
    let hostA = "Alex"
    let hostB = "Sam"

    // Models per Google's docs (June 2026). Swap if Google renames them.
    private let scriptModel = "gemini-2.5-flash"
    private let ttsModel = "gemini-2.5-flash-preview-tts"
    private let voiceA = "Kore"   // warm
    private let voiceB = "Puck"   // bright

    private let maxSourceCharacters = 14_000

    enum PodcastError: LocalizedError {
        case missingKey
        case emptySource
        case http(Int, String)
        case noScript
        case noAudio

        var errorDescription: String? {
            switch self {
            case .missingKey:      return "Add your Gemini API key first."
            case .emptySource:     return "No readable text found on the selected pages."
            case .noScript:        return "Gemini didn't return a script."
            case .noAudio:         return "Gemini didn't return audio."
            case .http(let code, let body):
                let detail = body.isEmpty ? "" : " — \(body.prefix(300))"
                return "Gemini request failed (HTTP \(code))\(detail)"
            }
        }
    }

    var hasKey: Bool { KeychainService.has(KeychainService.Account.gemini) }

    /// Full pipeline: script → multi-speaker audio → WAV file on disk.
    func makePodcast(
        title: String,
        sourceText: String,
        progress: @escaping (String) -> Void
    ) async throws -> (url: URL, durationSeconds: Double) {
        guard let key = KeychainService.get(KeychainService.Account.gemini), !key.isEmpty else {
            throw PodcastError.missingKey
        }
        let source = String(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxSourceCharacters))
        guard !source.isEmpty else { throw PodcastError.emptySource }

        progress("Writing the script…")
        let script = try await generateScript(from: source, topic: title, apiKey: key)

        progress("Recording the voices…")
        let pcm = try await synthesize(script: script, apiKey: key)

        progress("Finishing up…")
        let wav = Self.wav(fromPCM: pcm, sampleRate: 24_000, channels: 1, bitsPerSample: 16)
        let url = try save(wav, title: title)
        let duration = Double(pcm.count) / Double(24_000 * 2)   // bytes / (rate * bytesPerSample)
        return (url, duration)
    }

    // MARK: - Steps

    private func generateScript(from text: String, topic: String, apiKey: String) async throws -> String {
        let prompt = """
        You are producing a lively, accurate two-host podcast that explains the material below to a curious listener.
        The hosts are \(hostA) and \(hostB). Write roughly 2–4 minutes of natural, conversational dialogue that teaches the key ideas.
        Rules:
        - Every line MUST begin with the speaker's name and a colon, e.g. "\(hostA): ..." then "\(hostB): ...".
        - Alternate speakers; keep it engaging but faithful to the source — do not invent facts.
        - No markdown, no stage directions, no sound effects. Plain dialogue only.

        Topic: \(topic)

        Source material:
        \(text)
        """
        let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
        let json = try await post(model: scriptModel, body: body, apiKey: apiKey)
        guard let script = Self.firstText(in: json), !script.isEmpty else { throw PodcastError.noScript }
        return script
    }

    private func synthesize(script: String, apiKey: String) async throws -> Data {
        let body: [String: Any] = [
            "contents": [["parts": [["text": script]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "multiSpeakerVoiceConfig": [
                        "speakerVoiceConfigs": [
                            ["speaker": hostA, "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voiceA]]],
                            ["speaker": hostB, "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voiceB]]]
                        ]
                    ]
                ]
            ]
        ]
        let json = try await post(model: ttsModel, body: body, apiKey: apiKey)
        guard let b64 = Self.firstInlineAudio(in: json), let pcm = Data(base64Encoded: b64), !pcm.isEmpty else {
            throw PodcastError.noAudio
        }
        return pcm
    }

    // MARK: - Networking

    private func post(model: String, body: [String: Any], apiKey: String) async throws -> [String: Any] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")   // header, not URL — keeps key out of logs
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw PodcastError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PodcastError.http(code, "Unexpected response shape")
        }
        return json
    }

    // MARK: - Response parsing

    private static func parts(in json: [String: Any]) -> [[String: Any]] {
        let candidate = (json["candidates"] as? [[String: Any]])?.first
        let content = candidate?["content"] as? [String: Any]
        return (content?["parts"] as? [[String: Any]]) ?? []
    }

    private static func firstText(in json: [String: Any]) -> String? {
        parts(in: json).compactMap { $0["text"] as? String }.first
    }

    private static func firstInlineAudio(in json: [String: Any]) -> String? {
        parts(in: json).compactMap { ($0["inlineData"] as? [String: Any])?["data"] as? String }.first
    }

    // MARK: - WAV + disk

    private func save(_ wav: Data, title: String) throws -> URL {
        let dir = PathUtils.audioDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let name = "podcast-\(safe.prefix(40))-\(UUID().uuidString.prefix(8)).wav"
        let url = dir.appendingPathComponent(String(name))
        try wav.write(to: url)
        return url
    }

    /// Wrap little-endian PCM samples in a minimal 44-byte WAV header.
    static func wav(fromPCM pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        var header = Data()
        func ascii(_ s: String) { header.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + pcm.count)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(UInt16(blockAlign)); u16(UInt16(bitsPerSample))
        ascii("data"); u32(UInt32(pcm.count))

        var out = header
        out.append(pcm)
        return out
    }
}
