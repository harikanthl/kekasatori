//
//  StudyPackArchive.swift
//  MuseDrop
//
//  AppleArchive (LZFSE) container backing the `.kekapack` format. A study pack
//  is staged as a directory tree (manifest.json + verbatim canvas/paper dirs)
//  and archived natively — no base64 inflation, no third-party zip tooling,
//  symmetric encode/decode, and sandbox-safe.
//

import Foundation
import AppleArchive
import System

enum StudyPackArchive {
    enum ArchiveError: LocalizedError {
        case openFailed
        case streamSetupFailed

        var errorDescription: String? {
            switch self {
            case .openFailed: return "Couldn't open the study pack file."
            case .streamSetupFailed: return "Couldn't set up the study pack archive stream."
            }
        }
    }

    /// Archive the *contents* of `source` into a single LZFSE-compressed file.
    static func encode(directory source: URL, to destination: URL) throws {
        guard let fileStream = ArchiveByteStream.fileStream(
            path: FilePath(destination.path),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) else { throw ArchiveError.openFailed }
        defer { try? fileStream.close() }

        guard let compressStream = ArchiveByteStream.compressionStream(
            using: .lzfse,
            writingTo: fileStream
        ) else { throw ArchiveError.streamSetupFailed }
        defer { try? compressStream.close() }

        guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream) else {
            throw ArchiveError.streamSetupFailed
        }
        defer { try? encodeStream.close() }

        guard let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,CTM") else {
            throw ArchiveError.streamSetupFailed
        }
        try encodeStream.writeDirectoryContents(
            archiveFrom: FilePath(source.path),
            keySet: keySet
        )
    }

    /// Extract an archive produced by `encode` into `destination`.
    static func decode(_ archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let fileStream = ArchiveByteStream.fileStream(
            path: FilePath(archive.path),
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o644)
        ) else { throw ArchiveError.openFailed }
        defer { try? fileStream.close() }

        guard let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: fileStream) else {
            throw ArchiveError.streamSetupFailed
        }
        defer { try? decompressStream.close() }

        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream) else {
            throw ArchiveError.streamSetupFailed
        }
        defer { try? decodeStream.close() }

        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: FilePath(destination.path),
            flags: [.ignoreOperationNotPermitted]
        ) else { throw ArchiveError.streamSetupFailed }
        defer { try? extractStream.close() }

        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
    }
}
