//
//  LabEnvironment.swift
//  MuseDrop
//
//  An execution environment = a base image + optional package overlay. This is
//  where "plug-and-play HuggingFace" lives: curated presets carry transformers /
//  datasets / torch preinstalled so a workspace just picks one (docs/cockpit-
//  architecture.md §3.2). Named `LabEnvironment` to avoid colliding with
//  SwiftUI's `Environment`.
//
//  Phase A defines the object + presets; the CodeBox still drives images via
//  `CodeRunSpec.image` today. Later phases route an Environment into the
//  `RunRequest` (and build the `pipPackages` overlay as a cached image layer).
//

import Foundation

struct LabEnvironment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var baseImage: String
    var pipPackages: [String]
    var env: [String: String]
    var kind: Kind

    /// Batch images run a command and exit; interactive images host a long-lived
    /// server (notebook kernel) — the distinction the compute dial must respect.
    enum Kind: String, Codable, Equatable, Sendable {
        case batch
        case interactive
    }

    init(
        id: UUID = UUID(),
        name: String,
        baseImage: String,
        pipPackages: [String] = [],
        env: [String: String] = [:],
        kind: Kind = .batch
    ) {
        self.id = id
        self.name = name
        self.baseImage = baseImage
        self.pipPackages = pipPackages
        self.env = env
        self.kind = kind
    }
}

extension LabEnvironment {
    /// Curated, plug-and-play presets. Deterministic ids so a persisted reference
    /// survives relaunch (the seeds are fixed UUIDs, not random).
    static let presets: [LabEnvironment] = [
        LabEnvironment(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Python (slim)", baseImage: "python:3.12-slim"),
        LabEnvironment(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
            name: "PyTorch (CPU)", baseImage: "pytorch/pytorch:2.5.1-cpu"),
        LabEnvironment(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
            name: "HF Transformers",
            baseImage: "huggingface/transformers-pytorch-cpu:latest"),
        LabEnvironment(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!,
            name: "Data science (pandas)", baseImage: "amancevice/pandas:latest"),
        LabEnvironment(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!,
            name: "Notebook (marimo)",
            baseImage: "python:3.12-slim",
            pipPackages: ["marimo", "pandas", "numpy", "matplotlib"],
            kind: .interactive),
    ]

    static let defaultPreset = presets[0]
}
