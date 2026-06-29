//
//  Workspace.swift
//  MuseDrop
//
//  The cockpit's keystone object (Phase F): a research task that bundles a source
//  (a Discover paper, a cloned repo, or a notebook), a default environment +
//  compute target, its run history, and pointers into the app's own corpus
//  (papers / notes / transcripts / briefs) the agent may cite. Every other object
//  hangs off this one (docs/cockpit-architecture.md §3.1).
//

import Foundation

/// Where a workspace came from — the "New workspace from…" entry points.
enum WorkspaceSource: Codable, Equatable, Sendable {
    case blank
    case paper(paperID: String)        // from Discover
    case repo(url: URL, ref: String?)  // git clone (e.g. DeepSpec)
    case notebook(URL)

    var label: String {
        switch self {
        case .blank:            return "Blank"
        case .paper:            return "Paper"
        case .repo:             return "Repository"
        case .notebook:         return "Notebook"
        }
    }
}

/// A pointer into an existing pillar — how papers/notes/transcripts become
/// first-class context for the agent instead of copy-paste.
enum ContextRef: Codable, Equatable, Sendable, Identifiable {
    case paper(String)         // Discover paper id
    case note(UUID)            // study-pack note
    case transcript(UUID)      // transcription
    case researchBrief(UUID)   // DeepResearch output

    var id: String {
        switch self {
        case .paper(let p):         return "paper:\(p)"
        case .note(let u):          return "note:\(u.uuidString)"
        case .transcript(let u):    return "transcript:\(u.uuidString)"
        case .researchBrief(let u): return "brief:\(u.uuidString)"
        }
    }
}

struct Workspace: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var source: WorkspaceSource
    /// On-disk working directory (files, notebooks, artifacts). Nil until materialised.
    var rootDirectory: URL?
    var defaultEnvironmentID: UUID?
    var defaultTargetID: UUID?
    var runIDs: [UUID]
    var contextRefs: [ContextRef]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        source: WorkspaceSource = .blank,
        rootDirectory: URL? = nil,
        defaultEnvironmentID: UUID? = LabEnvironment.defaultPreset.id,
        defaultTargetID: UUID? = ComputeTarget.localID,
        contextRefs: [ContextRef] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.rootDirectory = rootDirectory
        self.defaultEnvironmentID = defaultEnvironmentID
        self.defaultTargetID = defaultTargetID
        self.runIDs = []
        self.contextRefs = contextRefs
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
