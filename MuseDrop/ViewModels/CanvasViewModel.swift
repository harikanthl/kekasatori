//
//  CanvasViewModel.swift
//  MuseDrop
//

import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class CanvasViewModel: ObservableObject {
    @Published var boards: [CanvasBoard] = []
    @Published var selectedBoardId: UUID?
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var exportError: String?
    
    let downloadId: UUID
    let mediaTitle: String
    
    private var bridge: ExcalidrawWebView.Coordinator?
    private var isBridgeReady = false
    private var pendingSceneJSON: String?
    private var saveTask: Task<Void, Never>?
    private var flushContinuation: CheckedContinuation<String?, Never>?
    private let logService = LogService.shared
    
    init(downloadId: UUID, mediaTitle: String) {
        self.downloadId = downloadId
        self.mediaTitle = mediaTitle
    }
    
    func bindBridge(_ coordinator: ExcalidrawWebView.Coordinator) {
        bridge = coordinator
    }
    
    func loadBoards() async {
        isLoading = true
        let persistence = await canvasPersistence()
        let list = await persistence.ensureDefaultBoards(for: downloadId)
        boards = list
        if selectedBoardId == nil {
            selectedBoardId = list.first?.id
        }
        isLoading = false
        
        if let boardId = selectedBoardId {
            await loadBoardScene(boardId)
        }
    }
    
    func selectBoard(_ boardId: UUID) async {
        await flushSave()
        selectedBoardId = boardId
        await loadBoardScene(boardId)
    }
    
    func createBoard(title: String = "New Board") async {
        let persistence = await canvasPersistence()
        guard let board = await persistence.createBoard(downloadId: downloadId, title: title) else { return }
        boards.append(board)
        await selectBoard(board.id)
    }
    
    func importFromStudyPack(_ analysis: MediaAnalysis) {
        guard let bridge, isBridgeReady else {
            statusMessage = "Canvas not ready yet"
            return
        }
        
        var batches: [CanvasElementBatch] = []
        if !analysis.summary.bullets.isEmpty {
            batches.append(CanvasAgentService.pushSummaryBullets(analysis.summary.bullets))
        }
        if !analysis.keyConcepts.isEmpty {
            batches.append(CanvasAgentService.pushConcepts(analysis.keyConcepts))
        }
        if !analysis.flashcards.isEmpty {
            let sample = Array(analysis.flashcards.prefix(8))
            batches.append(CanvasAgentService.pushFlashcards(sample))
        }
        
        for batch in batches {
            if let json = CanvasAgentService.encodeBatch(batch) {
                bridge.pushElementsJSON(json)
            }
        }
        statusMessage = "Imported study pack content"
        requestThumbnailSoon()
    }
    
    func handleBridgeMessage(_ message: ExcalidrawBridgeMessage) {
        Task { @MainActor in
            handleBridgeMessageOnMain(message)
        }
    }
    
    private func handleBridgeMessageOnMain(_ message: ExcalidrawBridgeMessage) {
        switch message.kind {
        case .ready:
            isBridgeReady = true
            applyTheme()
            if let pendingSceneJSON {
                bridge?.loadScene(
                    theme: ExcalidrawWebView.themeName(),
                    accentHex: ExcalidrawWebView.accentHex(from: .controlAccentColor),
                    sceneJSON: pendingSceneJSON
                )
                self.pendingSceneJSON = nil
            } else if let boardId = selectedBoardId {
                Task { await loadBoardScene(boardId) }
            }
        case .sceneChanged:
            guard let json = message.sceneJSON, let boardId = selectedBoardId else { return }
            // If a flush is awaiting the scene, hand it over directly and skip the
            // debounce so the edits are persisted before the view tears down.
            if flushContinuation != nil {
                resolveFlush(json)
            } else {
                scheduleSave(sceneJSON: json, boardId: boardId)
            }
        case .exportComplete:
            handleExport(message)
        case .thumbnailComplete:
            if let boardId = selectedBoardId,
               let base64 = message.base64,
               let data = Data(base64Encoded: base64) {
                Task {
                    await canvasPersistence().saveThumbnail(boardId: boardId, pngData: data)
                    await refreshBoardsList()
                }
            }
        case .error:
            exportError = message.errorMessage
            statusMessage = message.errorMessage
        }
    }
    
    func saveNow() {
        bridge?.requestSave()
    }
    
    func exportPNG() {
        bridge?.exportPNG()
    }
    
    func exportExcalidrawFile() {
        bridge?.exportJSON()
    }
    
    func shareExport() {
        exportPNG()
    }
    
    func handleDrop(providers: [NSItemProvider]) {
        guard let boardId = selectedBoardId else { return }
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let self else { return }
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        await self.importDroppedFile(url, boardId: boardId)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    guard let self else { return }
                    guard let image = object as? NSImage,
                          let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in
                        await self.importDroppedImageData(png, boardId: boardId)
                    }
                }
            }
        }
    }
    
    func flushSave() async {
        saveTask?.cancel()
        guard let bridge, isBridgeReady, let boardId = selectedBoardId else { return }

        // Ask the canvas for its current scene and wait for the round-trip, so we
        // persist the latest edits synchronously instead of relying on a debounce
        // that may not fire before the view is dismissed.
        let json: String? = await withCheckedContinuation { continuation in
            flushContinuation = continuation
            bridge.requestSave()
            // Safety net: never block teardown indefinitely if the bridge is gone.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.resolveFlush(nil)
            }
        }

        if let json {
            await canvasPersistence().saveScene(boardId: boardId, sceneJSON: json)
            isSaving = false
        }
    }

    private func resolveFlush(_ json: String?) {
        guard let continuation = flushContinuation else { return }
        flushContinuation = nil
        continuation.resume(returning: json)
    }

    // MARK: - Private
    
    private func canvasPersistence() async -> CanvasPersistenceActor {
        await MainActor.run { DataStore.shared.canvasPersistence }
    }
    
    private func loadBoardScene(_ boardId: UUID) async {
        let json = await canvasPersistence().loadSceneJSON(for: boardId)
        if isBridgeReady {
            bridge?.loadScene(
                theme: ExcalidrawWebView.themeName(),
                accentHex: ExcalidrawWebView.accentHex(from: .controlAccentColor),
                sceneJSON: json
            )
        } else {
            pendingSceneJSON = json
        }
    }
    
    private func scheduleSave(sceneJSON: String, boardId: UUID) {
        saveTask?.cancel()
        isSaving = true
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await canvasPersistence().saveScene(boardId: boardId, sceneJSON: sceneJSON)
            isSaving = false
            statusMessage = "Saved"
            requestThumbnailSoon()
        }
    }
    
    private func requestThumbnailSoon() {
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            bridge?.exportThumbnail()
        }
    }
    
    private func refreshBoardsList() async {
        let list = await canvasPersistence().boards(for: downloadId)
        boards = list
    }
    
    private func applyTheme() {
        bridge?.setTheme(
            theme: ExcalidrawWebView.themeName(),
            accentHex: ExcalidrawWebView.accentHex(from: .controlAccentColor)
        )
    }
    
    private func handleExport(_ message: ExcalidrawBridgeMessage) {
        if message.format == "excalidraw", let json = message.sceneJSON {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "excalidraw") ?? .json]
            panel.nameFieldStringValue = "\(mediaTitle)-canvas.excalidraw"
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                try? json.write(to: url, atomically: true, encoding: .utf8)
            }
            return
        }
        
        guard message.format == "png",
              let base64 = message.base64,
              let data = Data(base64Encoded: base64) else { return }
        
        let picker = NSSharingServicePicker(items: [data])
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }
    
    private func importDroppedFile(_ url: URL, boardId: UUID) async {
        let fileId = UUID().uuidString
        do {
            _ = try await canvasPersistence().importImageFile(boardId: boardId, sourceURL: url, fileId: fileId)
            statusMessage = "Image added to board files"
        } catch {
            logService.warning("Canvas file drop failed: \(error.localizedDescription)")
        }
    }
    
    private func importDroppedImageData(_ png: Data, boardId: UUID) async {
        let fileId = UUID().uuidString
        let filesDir = PathUtils.canvasFilesDirectory(boardId)
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let dest = filesDir.appendingPathComponent("\(fileId).png")
        try? png.write(to: dest)
        statusMessage = "Image saved to board"
    }
}
