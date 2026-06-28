//
//  OpenAICompatibleLLMClient.swift
//  MuseDrop
//
//  One client for every OpenAI-compatible gateway: OpenRouter (default),
//  OpenAI, DeepSeek, Kimi/Moonshot, Gemini (OpenAI-compat), Ollama, LM Studio.
//  Streams `POST {baseURL}/chat/completions` Server-Sent Events.
//

import Foundation

struct OpenAICompatibleLLMClient: LLMClient {
    let baseURL: String
    let apiKey: String?
    /// Optional attribution headers (OpenRouter ranks apps by these).
    var referer: String = "https://kekasatori.app"
    var appTitle: String = "Kekasatori"

    private func makeRequest(messages: [LLMMessage], model: String) throws -> URLRequest {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBase.isEmpty, let url = URL(string: trimmedBase + "/chat/completions") else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // OpenRouter attribution (ignored by other gateways).
        request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(appTitle, forHTTPHeaderField: "X-Title")

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages.map(Self.encodeMessage)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// Serializes one message to the OpenAI chat schema. Text-only messages use
    /// the plain `content: String` form; messages carrying images use the
    /// content-parts array (`text` + `image_url` with base64 data URLs).
    private static func encodeMessage(_ msg: LLMMessage) -> [String: Any] {
        guard !msg.images.isEmpty else {
            return ["role": msg.role.rawValue, "content": msg.content]
        }
        var parts: [[String: Any]] = []
        if !msg.content.isEmpty {
            parts.append(["type": "text", "text": msg.content])
        }
        for png in msg.images {
            let dataURL = "data:image/png;base64,\(png.base64EncodedString())"
            parts.append(["type": "image_url", "image_url": ["url": dataURL]])
        }
        return ["role": msg.role.rawValue, "content": parts]
    }

    func stream(messages: [LLMMessage], model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages: messages, model: model)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        // Drain a little of the error body for a useful message.
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 600 { break } }
                        throw LLMError.http(status: http.statusCode, body: body)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let delta = Self.parseDelta(data) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Extracts `choices[0].delta.content` from a streaming chunk.
    private static func parseDelta(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else {
            return nil
        }
        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String, !content.isEmpty {
            return content
        }
        // Some gateways send the final token under "message".
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String, !content.isEmpty {
            return content
        }
        return nil
    }
}
