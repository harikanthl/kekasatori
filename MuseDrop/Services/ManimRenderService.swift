//
//  ManimRenderService.swift
//  MuseDrop
//

import Foundation

enum ManimRenderError: LocalizedError {
    case manimNotInstalled
    case latexNotInstalled
    case sceneTemplateMissing
    case renderFailed(String)
    case outputMissing
    case unsafeLatex

    var errorDescription: String? {
        switch self {
        case .manimNotInstalled:
            return "Manim is not installed. Run `brew install manim` in Terminal."
        case .latexNotInstalled:
            return "LaTeX is not installed. Run `brew install --cask basictex` then `sudo tlmgr install amsfonts standalone preview dvisvgm`."
        case .unsafeLatex:
            return "That formula contains LaTeX commands that aren't allowed for animation."
        case .sceneTemplateMissing:
            return "Bundled Manim scene template is missing from the app."
        case .renderFailed(let detail):
            return "Manim render failed: \(detail)"
        case .outputMissing:
            return "Manim finished but no video file was produced."
        }
    }
}

struct ManimRenderJob: Sendable {
    let downloadId: UUID
    let dayKey: String
    let latex: String
    let sceneType: ManimSceneType
    let style: ManimAnimationStyle
    let quality: ManimRenderQuality
    let title: String?
}

actor ManimRenderService {
    static let shared = ManimRenderService()
    
    private let runner = ProcessRunner()
    private let logService = LogService.shared
    
    func render(_ job: ManimRenderJob) async throws -> NotebookAnimationRecord {
        // Final gate: never feed file/shell LaTeX primitives to the system latex
        // compiler, regardless of which path built this job.
        guard LatexBlockParser.isSafeForManim(job.latex) else {
            throw ManimRenderError.unsafeLatex
        }

        let status = await ManimEnvironment.check()
        guard status.manimPath != nil else { throw ManimRenderError.manimNotInstalled }
        guard status.latexPath != nil else { throw ManimRenderError.latexNotInstalled }
        guard let manimPath = status.manimPath else { throw ManimRenderError.manimNotInstalled }
        
        let recordId = UUID()
        let videoFileName = "\(recordId.uuidString).mp4"
        let jobDir = PathUtils.manimJobDirectory(
            downloadId: job.downloadId,
            dayKey: job.dayKey,
            jobId: recordId
        )
        
        try FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: jobDir) }

        let sceneURL = jobDir.appendingPathComponent(ManimSceneTemplate.fileName)
        do {
            try ManimSceneTemplate.writeScene(to: sceneURL)
        } catch {
            throw ManimRenderError.sceneTemplateMissing
        }
        
        let jobPayload = makeJobPayload(job: job)
        let jobJSON = jobDir.appendingPathComponent("job.json")
        try JSONEncoder().encode(jobPayload).write(to: jobJSON)
        
        let mediaDir = jobDir.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        
        let sceneClass = job.sceneType.manimSceneClass
        
        let arguments = [
            "render",
            job.quality.manimFlag,
            "--disable_caching",
            "--format", "mp4",
            "--media_dir", mediaDir.path,
            "-o", videoFileName,
            sceneURL.lastPathComponent,
            sceneClass
        ]
        
        logService.info("Manim render starting: \(job.latex.prefix(80))")
        
        let result = try await runner.run(
            executable: manimPath,
            arguments: arguments,
            workingDirectory: jobDir,
            timeout: 600
        )
        
        guard result.exitCode == 0 else {
            let detail = trimmedTail(result.stderr.isEmpty ? result.stdout : result.stderr)
            throw ManimRenderError.renderFailed(detail)
        }
        
        guard let rendered = findRenderedVideo(in: mediaDir, preferredName: videoFileName) else {
            throw ManimRenderError.outputMissing
        }
        
        let destination = NotebookAnimationStore.videoURL(
            downloadId: job.downloadId,
            dayKey: job.dayKey,
            fileName: videoFileName
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: rendered, to: destination)

        let record = NotebookAnimationRecord(
            id: recordId,
            latex: job.latex,
            sceneType: job.sceneType,
            style: job.style,
            quality: job.quality,
            videoFileName: videoFileName
        )
        
        try NotebookAnimationStore.append(record, downloadId: job.downloadId, dayKey: job.dayKey)
        logService.info("Manim render complete: \(destination.path)")
        return record
    }
    
    // MARK: - Private
    
    private func makeJobPayload(job: ManimRenderJob) -> ManimSceneJobPayload {
        ManimScenePlanner.buildJob(
            latex: job.latex,
            sceneType: job.sceneType,
            style: job.style,
            title: job.title
        )
    }
    
    private func findRenderedVideo(in mediaDir: URL, preferredName: String) -> URL? {
        if let enumerator = FileManager.default.enumerator(
            at: mediaDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            var matches: [URL] = []
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "mp4" {
                matches.append(url)
            }
            // Only accept the exact expected filename. Each job uses a fresh media
            // dir, so anything else would be a stale/unexpected artifact.
            return matches.first(where: { $0.lastPathComponent == preferredName })
        }

        return nil
    }
    
    private func trimmedTail(_ text: String, maxLength: Int = 800) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return "…" + String(trimmed.suffix(maxLength))
    }
}
