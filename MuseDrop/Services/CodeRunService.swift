//
//  CodeRunService.swift
//  MuseDrop
//
//  Runs a snippet inside a container for the Code box: stage the code to a temp
//  workdir, mount it, and execute in the chosen image. The same image can later
//  run on a remote GPU, so "the same thing" runs locally and remotely. Command
//  building is pure (tested); streaming is driven by ProcessRunner.
//
//  Local containers are CPU-only (no Mac GPU passthrough) — GPU is the remote
//  RunPod tier.
//

import Foundation

struct CodeRunSpec: Equatable {
    enum Language: String, CaseIterable, Identifiable, Codable {
        case python
        case bash

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .python: return "Python"
            case .bash:   return "Shell"
            }
        }
        var defaultImage: String {
            switch self {
            case .python: return "python:3.12-slim"
            case .bash:   return "alpine:latest"
            }
        }
        var fileName: String {
            switch self {
            case .python: return "main.py"
            case .bash:   return "main.sh"
            }
        }
        func runCommand(file: String) -> [String] {
            switch self {
            case .python: return ["python", file]
            case .bash:   return ["sh", file]
            }
        }
        var starter: String {
            switch self {
            case .python: return "import sys\nprint('Hello from', sys.version.split()[0])\n"
            case .bash:   return "echo \"Hello from $(uname -m) container\"\n"
            }
        }
    }

    var language: Language = .python
    /// Image override; empty falls back to the language default.
    var image: String = ""
    var code: String = ""
    /// Bundled data files to copy into the workdir before running (by file name,
    /// resolved from the app bundle). Used by Learn data-cleaning challenges that
    /// ship a real dataset. Empty for code snippets that generate their own data.
    var dataFiles: [String] = []
    /// Environment variables passed to the container (e.g. KAGGLE_USERNAME /
    /// KAGGLE_KEY for Kaggle lessons). Empty for most runs.
    var env: [String: String] = [:]

    var resolvedImage: String { image.isEmpty ? language.defaultImage : image }
}

enum CodeRunError: LocalizedError {
    case missingDataFile(String)

    var errorDescription: String? {
        switch self {
        case .missingDataFile(let name): return "Bundled data file not found: \(name)"
        }
    }
}

enum CodeRunService {
    /// `run --rm [-e K=V ...] -v <hostWorkdir>:/work -w /work <image> <runCommand>`.
    /// Pure; env vars are sorted for deterministic output.
    static func buildArguments(image: String, hostWorkdir: String, runCommand: [String],
                               env: [String: String] = [:]) -> [String] {
        var args = ["run", "--rm"]
        for key in env.keys.sorted() {
            args += ["-e", "\(key)=\(env[key]!)"]
        }
        args += ["-v", "\(hostWorkdir):/work", "-w", "/work", image]
        return args + runCommand
    }

    /// Stage the code (and any bundled data files) into a fresh temp workdir.
    static func stage(_ spec: CodeRunSpec) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kekacode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(spec.language.fileName)
        try spec.code.write(to: file, atomically: true, encoding: .utf8)

        for name in spec.dataFiles {
            guard let source = bundledDataURL(name) else {
                throw CodeRunError.missingDataFile(name)
            }
            let dest = dir.appendingPathComponent((name as NSString).lastPathComponent)
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return dir
    }

    /// Resolve a bundled challenge data file (flattened or under `ChallengeData/`).
    static func bundledDataURL(_ name: String) -> URL? {
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        let withExt = ext.isEmpty ? nil : ext
        return Bundle.main.url(forResource: base, withExtension: withExt)
            ?? Bundle.main.url(forResource: base, withExtension: withExt, subdirectory: "ChallengeData")
    }
}
