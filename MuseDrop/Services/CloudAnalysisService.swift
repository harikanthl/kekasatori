//
//  CloudAnalysisService.swift
//  MuseDrop
//
//  Generates a study pack from a transcript in a SINGLE call to the user's
//  configured BYOK provider, using native structured output (response_format
//  json_schema → constrained decoding, schema-valid JSON, no brace-scraping).
//  (We tried a concurrent per-artifact fan-out, but it sent the whole paper as
//  input N times — on a throttled free tier those calls serialize, so the
//  duplicated prefill made it ~50% slower per page than this single call. One
//  call sends the document once.) Providers that reject response_format degrade
//  to prose-JSON automatically. The on-device path remains the fallback if this
//  throws.
//

import Foundation

enum CloudAnalysisService {
    /// One call → full `MediaAnalysisPayload`. Throws if no key, or on transport /
    /// parse failure (the caller then falls back to on-device).
    ///
    /// `onPartial` is accepted for call-site compatibility but unused here — a
    /// single call can't emit partial artifacts. (Kept so progressive streaming
    /// can be reintroduced later, e.g. on a paid tier where fan-out pays off.)
    static func analyze(
        transcript: String,
        title: String,
        settings: LLMProviderSettings,
        researchContext: String?,
        onPartial: (@Sendable (MediaAnalysisPayload) -> Void)? = nil
    ) async throws -> MediaAnalysisPayload {
        guard let account = settings.preset.keychainAccount,
              let key = KeychainService.get(account), !key.isEmpty else {
            throw LLMError.missingAPIKey
        }
        let client = OpenAICompatibleLLMClient(baseURL: settings.effectiveBaseURL, apiKey: key)
        let prompt = buildPrompt(transcript: transcript, title: title, researchContext: researchContext)
        let messages = [
            LLMMessage(.system, "You are a study-material generator. Reply with ONLY a single JSON object — no prose, no markdown fences."),
            LLMMessage(.user, prompt)
        ]
        let responseFormat: [String: Any] = [
            "type": "json_schema",
            "json_schema": ["name": "study_pack", "schema": Self.studyPackSchema]
        ]

        // Prefer native structured output (constrained decoding → schema-valid JSON,
        // no brace-scraping, no parse-failure fall back to on-device). If a provider
        // rejects response_format (400), retry once in plain prose-JSON mode so every
        // BYOK gateway still works.
        var useStructured = true
        var attempt = 0
        while true {
            do {
                let raw = useStructured
                    ? try await client.completeJSON(messages: messages, model: settings.modelId, responseFormat: responseFormat)
                    : try await client.complete(messages: messages, model: settings.modelId)
                return try parse(raw, title: title)
            } catch let LLMError.http(code, _) where code == 400 && useStructured {
                useStructured = false   // provider doesn't support json_schema — degrade
            } catch let LLMError.http(code, _) where (code == 429 || code == 503) && attempt < 2 {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
            }
        }
    }

    /// JSON Schema matching `parse(_:title:)`. No `strict`/`additionalProperties:false`
    /// — keeps it portable across providers (OpenAI strict mode and Gemini-compat
    /// have differing requirements; best-effort schema works on both).
    private static let studyPackSchema: [String: Any] = {
        func arr(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
        let str: [String: Any] = ["type": "string"]
        let strings = arr(str)
        return [
            "type": "object",
            "properties": [
                "summary": [
                    "type": "object",
                    "properties": ["oneLine": str, "paragraph": str, "bullets": strings],
                    "required": ["oneLine", "paragraph", "bullets"]
                ],
                "notes": [
                    "type": "object",
                    "properties": [
                        "sections": arr([
                            "type": "object",
                            "properties": ["heading": str, "content": str, "bullets": strings],
                            "required": ["heading", "content", "bullets"]
                        ])
                    ],
                    "required": ["sections"]
                ],
                "keyConcepts": arr([
                    "type": "object",
                    "properties": [
                        "term": str, "definition": str,
                        "importance": ["type": "string", "enum": ["high", "medium", "low"]]
                    ],
                    "required": ["term", "definition", "importance"]
                ]),
                "flashcards": arr([
                    "type": "object",
                    "properties": ["front": str, "back": str, "tag": str],
                    "required": ["front", "back", "tag"]
                ]),
                "mindMap": [
                    "type": "object",
                    "properties": [
                        "centralTopic": str,
                        "nodes": arr([
                            "type": "object",
                            "properties": ["label": str, "level": ["type": "integer"]],
                            "required": ["label", "level"]
                        ]),
                        "edges": arr([
                            "type": "object",
                            "properties": ["from": str, "to": str, "relationship": str],
                            "required": ["from", "to", "relationship"]
                        ])
                    ],
                    "required": ["centralTopic", "nodes", "edges"]
                ]
            ],
            "required": ["summary", "notes", "keyConcepts", "flashcards", "mindMap"]
        ]
    }()

    // MARK: - Prompt

    private static func buildPrompt(transcript: String, title: String, researchContext: String?) -> String {
        let research = (researchContext?.isEmpty == false)
            ? "\n\nAdditional external context you may use:\n\(researchContext!)\n"
            : ""
        return """
        Create a study pack for the material titled "\(title)".

        Return ONE JSON object with EXACTLY this shape (no extra keys, no commentary):
        {
          "summary": { "oneLine": "string", "paragraph": "string", "bullets": ["string", ...] },
          "notes": { "sections": [ { "heading": "string", "content": "string", "bullets": ["string", ...] } ] },
          "keyConcepts": [ { "term": "string", "definition": "string", "importance": "high|medium|low" } ],
          "flashcards": [ { "front": "string", "back": "string", "tag": "string" } ],
          "mindMap": {
            "centralTopic": "string",
            "nodes": [ { "label": "string", "level": 1 } ],
            "edges": [ { "from": "node label", "to": "node label", "relationship": "string" } ]
          }
        }

        Guidance:
        - summary.bullets: 4–8 crisp takeaways.
        - notes.sections: 4–8 sections, each with a heading, a short paragraph, and 2–5 bullets.
        - keyConcepts: 6–12 of the most important terms.
        - flashcards: 8–16 question/answer pairs covering the key ideas.
        - mindMap: centralTopic = the core subject; 5–9 level-1 nodes; edges connect node labels (you may also add level-2 nodes). Use the exact node "label" strings in edges.
        - Be accurate to the source; do not invent facts.\(research)

        Source material:
        \"\"\"
        \(transcript)
        \"\"\"
        """
    }

    // MARK: - Parsing

    private static func parse(_ raw: String, title: String) throws -> MediaAnalysisPayload {
        guard let data = extractJSON(raw),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decoding("No JSON object in the model response.")
        }

        let summaryObj = root["summary"] as? [String: Any] ?? [:]
        let summary = SummaryResult(
            oneLine: (summaryObj["oneLine"] as? String) ?? title,
            paragraph: (summaryObj["paragraph"] as? String) ?? "",
            bullets: stringArray(summaryObj["bullets"]))

        let notesObj = root["notes"] as? [String: Any] ?? [:]
        let sections = (notesObj["sections"] as? [[String: Any]] ?? []).compactMap { s -> NoteSection? in
            let heading = (s["heading"] as? String) ?? ""
            let content = (s["content"] as? String) ?? ""
            if heading.isEmpty && content.isEmpty { return nil }
            return NoteSection(heading: heading, content: content, bullets: stringArray(s["bullets"]))
        }
        let notes = StudyNotes(title: "\(title) — Study Notes", sections: sections)

        let concepts = (root["keyConcepts"] as? [[String: Any]] ?? []).compactMap { c -> KeyConcept? in
            guard let term = c["term"] as? String, !term.isEmpty else { return nil }
            return KeyConcept(term: term,
                              definition: (c["definition"] as? String) ?? "",
                              importance: (c["importance"] as? String) ?? "medium")
        }

        let cards = (root["flashcards"] as? [[String: Any]] ?? []).compactMap { f -> FlashCard? in
            guard let front = f["front"] as? String, !front.isEmpty else { return nil }
            return FlashCard(front: front, back: (f["back"] as? String) ?? "", tag: (f["tag"] as? String) ?? "general")
        }

        let mindMap = parseMindMap(root["mindMap"] as? [String: Any], title: title, concepts: concepts)

        guard !summary.paragraph.isEmpty || !sections.isEmpty || !cards.isEmpty || !concepts.isEmpty else {
            throw LLMError.decoding("Model returned an empty study pack.")
        }

        return MediaAnalysisPayload(
            summary: summary, notes: notes, keyConcepts: concepts,
            flashcards: cards, mindMap: mindMap, engine: .cloud)
    }

    /// Build a MindMap, mapping node labels to generated IDs for the edges.
    /// Falls back to a concept-derived map when nodes are missing/empty.
    private static func parseMindMap(_ obj: [String: Any]?, title: String, concepts: [KeyConcept]) -> MindMap {
        let central = (obj?["centralTopic"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? title

        let rawNodes = obj?["nodes"] as? [[String: Any]] ?? []
        var nodes: [MindMapNode] = []
        var idByLabel: [String: String] = [:]
        for n in rawNodes {
            guard let label = n["label"] as? String, !label.isEmpty else { continue }
            let level = (n["level"] as? Int) ?? 1
            let node = MindMapNode(label: label, level: max(1, level))
            nodes.append(node)
            idByLabel[label.lowercased()] = node.id
        }

        if nodes.isEmpty {
            for c in concepts.prefix(8) {
                let node = MindMapNode(label: c.term, level: 1)
                nodes.append(node)
                idByLabel[c.term.lowercased()] = node.id
            }
            return MindMap(centralTopic: central, nodes: nodes, edges: [])
        }

        let rawEdges = obj?["edges"] as? [[String: Any]] ?? []
        let edges: [MindMapEdge] = rawEdges.compactMap { e in
            guard let from = (e["from"] as? String)?.lowercased(),
                  let to = (e["to"] as? String)?.lowercased(),
                  let fromId = idByLabel[from], let toId = idByLabel[to] else { return nil }
            return MindMapEdge(fromId: fromId, toId: toId, relationship: (e["relationship"] as? String) ?? "relates to")
        }
        return MindMap(centralTopic: central, nodes: nodes, edges: edges)
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [String])?.filter { !$0.isEmpty } ?? []
    }

    private static func extractJSON(_ raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end {
            return String(trimmed[start...end]).data(using: .utf8)
        }
        return nil
    }
}
