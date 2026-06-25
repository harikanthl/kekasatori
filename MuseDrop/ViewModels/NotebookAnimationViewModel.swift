//
//  NotebookAnimationViewModel.swift
//  MuseDrop
//

import Foundation
import AVFoundation
import AppKit

@MainActor
final class NotebookAnimationViewModel: ObservableObject {
    @Published var latexInput: String = ""
    @Published var selectedSceneType: ManimSceneType = .auto
    @Published var selectedStyle: ManimAnimationStyle = .write
    @Published var selectedQuality: ManimRenderQuality = .draft
    @Published var animations: [NotebookAnimationRecord] = []
    @Published var environmentStatus: ManimEnvironmentStatus?
    @Published var isRendering = false
    @Published var renderProgressMessage: String?
    @Published var errorMessage: String?
    @Published var previewPlayer: AVPlayer?
    @Published var previewRecord: NotebookAnimationRecord?
    
    let downloadId: UUID
    var dayKey: String
    let mediaTitle: String
    
    init(downloadId: UUID, dayKey: String, mediaTitle: String) {
        self.downloadId = downloadId
        self.dayKey = dayKey
        self.mediaTitle = mediaTitle
    }
    
    func refreshEnvironment() async {
        environmentStatus = await ManimEnvironment.check()
    }
    
    func loadAnimations() {
        animations = NotebookAnimationStore.load(downloadId: downloadId, dayKey: dayKey).animations
    }
    
    func applyNotebookContext(text: String, selection: String?) {
        if let primary = LatexBlockParser.primary(from: text, selection: selection) {
            latexInput = primary
        } else if latexInput.isEmpty, LatexBlockParser.isLikelyMath(selection ?? "") {
            latexInput = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }
    
    func render() async -> NotebookAnimationRecord? {
        let latex = latexInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty else {
            errorMessage = "Enter or select a LaTeX formula to animate."
            return nil
        }

        // Reject file/shell LaTeX primitives before they reach the system latex
        // compiler that Manim drives (typed input bypasses the extractor's check).
        guard LatexBlockParser.isSafeForManim(latex) else {
            errorMessage = "That formula contains LaTeX commands that aren't allowed for animation."
            return nil
        }

        errorMessage = nil
        isRendering = true
        renderProgressMessage = "Rendering with Manim…"
        
        let job = ManimRenderJob(
            downloadId: downloadId,
            dayKey: dayKey,
            latex: latex,
            sceneType: selectedSceneType,
            style: selectedStyle,
            quality: selectedQuality,
            title: mediaTitle
        )
        
        defer { isRendering = false }
        
        do {
            let record = try await ManimRenderService.shared.render(job)
            animations.insert(record, at: 0)
            renderProgressMessage = "Added to notebook"
            play(record)
            return record
        } catch {
            errorMessage = error.localizedDescription
            renderProgressMessage = nil
            return nil
        }
    }
    
    func play(_ record: NotebookAnimationRecord) {
        previewRecord = record
        let url = NotebookAnimationStore.resolvedVideoURL(
            for: record,
            downloadId: downloadId,
            dayKey: dayKey
        )
        previewPlayer?.pause()
        previewPlayer = AVPlayer(url: url)
        previewPlayer?.play()
    }
    
    func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        previewRecord = nil
    }
    
    func delete(_ record: NotebookAnimationRecord) async {
        do {
            try NotebookAnimationStore.delete(
                record: record,
                downloadId: downloadId,
                dayKey: dayKey
            )
            animations.removeAll { $0.id == record.id }
            if previewRecord?.id == record.id {
                stopPreview()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func revealInFinder(_ record: NotebookAnimationRecord) {
        let url = NotebookAnimationStore.resolvedVideoURL(
            for: record,
            downloadId: downloadId,
            dayKey: dayKey
        )
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
