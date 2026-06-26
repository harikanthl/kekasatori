//
//  StudyPackBundle.swift
//  MuseDrop
//
//  A self-contained, shareable study pack (".kekapack"). This is the portable
//  on-disk format that backs export/import today and will back community
//  sharing later — the same bundle is what we'll content-address (IPFS CID)
//  and post to the discovery wall in a future phase.
//
//  Format 2 is an AppleArchive (LZFSE) container: a `manifest.json` (this
//  struct, encoded) plus verbatim `canvas/<n>/` and `papers/0/` directories.
//  Canvas/paper payloads reference their archive-relative `directory`; the
//  files live in the archive, not inline. Format 1 packs were a single JSON
//  file with files inlined as base64 (`files`) — still readable for back-compat.
//

import Foundation
import UniformTypeIdentifiers

struct StudyPackBundle: Codable {
    /// 1 = single JSON file (legacy, base64-inlined files). 2 = AppleArchive
    /// container with a manifest + verbatim directories. Readers accept any
    /// version `<= currentFormatVersion`.
    static let currentFormatVersion = 2

    var formatVersion: Int
    var app: String
    var appVersion: String?
    var exportedAt: Date
    var source: Source
    var analysis: MediaAnalysis
    /// Canvas/Excalidraw boards attached to the source, captured verbatim.
    var canvasBoards: [CanvasBoardPayload]?
    /// Research-paper bundle (PDF/HTML/metadata) when the source is a paper.
    var papers: [PaperPayload]?

    struct Source: Codable {
        /// Human-readable title of the original media/paper.
        var title: String
        /// Original media or paper URL when known (informational).
        var sourceURL: String?
        /// `DownloadRecord.format`, so a paper's source kind round-trips and the
        /// importer recognizes it as a research document.
        var format: String?
    }

    init(
        analysis: MediaAnalysis,
        sourceTitle: String,
        sourceURL: String?,
        sourceFormat: String? = nil,
        canvasBoards: [CanvasBoardPayload]? = nil,
        papers: [PaperPayload]? = nil,
        appVersion: String? = StudyPackBundle.hostAppVersion,
        exportedAt: Date = Date()
    ) {
        self.formatVersion = StudyPackBundle.currentFormatVersion
        self.app = "Kekasatori"
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.source = Source(title: sourceTitle, sourceURL: sourceURL, format: sourceFormat)
        self.analysis = analysis
        self.canvasBoards = canvasBoards
        self.papers = papers
    }

    static var hostAppVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

/// One canvas board's metadata plus a pointer to its files. Format 2 sets
/// `directory` (archive-relative); format 1 set `files` (inline base64).
struct CanvasBoardPayload: Codable {
    var title: String
    var kindRaw: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    /// Archive-relative directory holding this board's files (format 2).
    var directory: String?
    /// Inline base64 files (legacy format 1). Mutually exclusive with `directory`.
    var files: [FileBlob]?
}

/// A research-paper bundle (metadata.json, paper.pdf, paper.html, article.txt),
/// referenced by archive `directory` (format 2) or inline `files` (format 1).
struct PaperPayload: Codable {
    var directory: String?
    var files: [FileBlob]?
}

/// A single file's bytes as base64, keyed by its path relative to a captured
/// directory root. Only used to *read* legacy format-1 packs.
struct FileBlob: Codable {
    var path: String
    var base64: String
}

/// Restores legacy format-1 base64 `FileBlob`s back into a directory.
enum DirectoryArchive {
    static func restore(_ blobs: [FileBlob], to directory: URL) throws {
        let fm = FileManager.default
        for blob in blobs {
            // Reject absolute paths and traversal — packs come from other people.
            guard !blob.path.hasPrefix("/"),
                  !blob.path.split(separator: "/").contains("..") else { continue }
            guard let data = Data(base64Encoded: blob.base64) else { continue }
            let dest = directory.appendingPathComponent(blob.path)
            try fm.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: dest)
        }
    }
}

/// A study pack assembled for export: the manifest plus the on-disk source
/// directories to stage into the archive, keyed by archive-relative path.
struct StudyPackExport {
    let bundle: StudyPackBundle
    let fileSources: [String: URL]
}

/// A decoded study pack ready to import: the manifest plus, for format-2 packs,
/// the temporary directory the archive was extracted into (nil for legacy).
struct DecodedStudyPack {
    let bundle: StudyPackBundle
    let rootDirectory: URL?
}

enum StudyPackBundleError: LocalizedError {
    /// The file declares a format version this build doesn't understand.
    case unsupportedFormat(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(found, supported):
            return "This study pack was made with a newer version of Kekasatori "
                + "(format \(found); this app supports up to \(supported)). "
                + "Update Kekasatori and try again."
        }
    }
}

extension UTType {
    /// The ".kekapack" container type, declared as an exported type in
    /// Info.plist (`com.kekasatori.studypack`). Resolving by that identifier is
    /// what lets the open panel *enable* `.kekapack` files — a purely dynamic
    /// type does not, because the system maps the unknown extension to a
    /// different generic UTI and greys the file out. Falls back to a dynamic
    /// type / JSON if the declaration isn't registered yet.
    static var kekaPack: UTType {
        UTType("com.kekasatori.studypack")
            ?? UTType(filenameExtension: "kekapack", conformingTo: .data)
            ?? .data
    }
}
