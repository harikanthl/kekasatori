//
//  MCPServerConnector.swift
//  MuseDrop
//
//  Phase 5a follow-up — connect the embedded `kekasatori-mcp` server to MCP
//  clients without hand-editing config paths. Locates the binary shipped inside
//  the app bundle, generates the standard `mcpServers` JSON (Cursor / Claude
//  Desktop), and can register it with the Claude Code CLI.
//

import Foundation

struct MCPServerConnector: Sendable {
    static let serverName = "kekasatori"
    static let executableName = "kekasatori-mcp"

    /// The embedded server binary (sibling of the app executable in
    /// Contents/MacOS), or nil if missing (e.g. running tests / not embedded).
    let binaryURL: URL?

    init() {
        binaryURL = Bundle.main.url(forAuxiliaryExecutable: Self.executableName)
    }

    /// Test seam.
    init(binaryURL: URL?) {
        self.binaryURL = binaryURL
    }

    var isAvailable: Bool { binaryURL != nil }

    // MARK: - Client config

    /// `mcpServers` JSON snippet for clients that read a config file (Cursor,
    /// Claude Desktop). Uses the embedded path when available.
    func configJSON() -> String {
        Self.configJSON(serverName: Self.serverName,
                        path: binaryURL?.path ?? "/path/to/\(Self.executableName)")
    }

    static func configJSON(serverName: String, path: String) -> String {
        struct Entry: Encodable { let command: String }
        struct Root: Encodable { let mcpServers: [String: Entry] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(Root(mcpServers: [serverName: Entry(command: path)])),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    /// Arguments for `claude mcp add <name> <path>`.
    static func claudeAddArguments(serverName: String, path: String) -> [String] {
        ["mcp", "add", serverName, path]
    }

    // MARK: - Claude Code registration

    /// Locate the Claude Code CLI (`claude`) on PATH, or nil if not installed.
    func claudeCodeExecutable() async -> URL? {
        let runner = ProcessRunner()
        guard let result = try? await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/which"),
            arguments: ["claude"]
        ), result.exitCode == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    /// Register the server with Claude Code via `claude mcp add`.
    func connectClaudeCode() async -> (ok: Bool, message: String) {
        guard let binaryURL else {
            return (false, "Server binary isn’t in the app bundle. Build & run the app from a full build.")
        }
        guard let claude = await claudeCodeExecutable() else {
            return (false, "Claude Code CLI (`claude`) wasn’t found. Install it, then try again.")
        }
        let runner = ProcessRunner()
        do {
            let result = try await runner.run(
                executable: claude,
                arguments: Self.claudeAddArguments(serverName: Self.serverName, path: binaryURL.path)
            )
            if result.exitCode == 0 {
                return (true, "Added “\(Self.serverName)” to Claude Code.")
            }
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            return (false, detail.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
