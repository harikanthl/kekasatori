//
//  MCPTool.swift
//  MuseDrop
//
//  Phase 5a.1 — the transport-agnostic MCP tool layer. Each `MCPTool` is a name,
//  a human description, a JSON-Schema for its arguments, and an async handler
//  that takes raw JSON argument bytes and returns raw JSON result bytes.
//
//  Keeping the boundary as JSON `Data` (not the official SDK's `Value` type) lets
//  the cockpit's tools be built and unit-tested in the app target now, with zero
//  project-file changes. Phase 5a.2 adds the CLI target + official swift-sdk and
//  adapts its `Value` ⇄ `Data` at the stdio edge — these handlers don't change.
//

import Foundation

/// A single MCP tool: metadata + a JSON-in/JSON-out handler.
struct MCPTool: Sendable {
    let name: String
    let description: String
    /// JSON Schema (an object) describing the arguments, as a JSON string.
    let inputSchemaJSON: String
    /// Decode the argument JSON, run, and return the result JSON. Throws
    /// `MCPToolError` on malformed/invalid input.
    let invoke: @Sendable (Data) async throws -> Data
}

enum MCPToolError: LocalizedError, Equatable {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let detail): return "Invalid arguments: \(detail)"
        }
    }
}

extension MCPTool {
    /// Build a tool from typed `Args`/`Result` Codable types. Handles arg decoding
    /// (mapping decode failures to `MCPToolError.invalidArguments`) and result
    /// encoding, so handlers stay in typed Swift.
    static func typed<Args: Decodable, Result: Encodable>(
        name: String,
        description: String,
        inputSchemaJSON: String,
        run: @escaping @Sendable (Args) async throws -> Result
    ) -> MCPTool {
        MCPTool(name: name, description: description, inputSchemaJSON: inputSchemaJSON) { data in
            let args: Args
            do {
                args = try JSONDecoder().decode(Args.self, from: data)
            } catch {
                throw MCPToolError.invalidArguments(error.localizedDescription)
            }
            let result = try await run(args)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(result)
        }
    }
}
