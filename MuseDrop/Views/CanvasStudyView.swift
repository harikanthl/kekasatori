//
//  CanvasStudyView.swift
//  MuseDrop
//

import SwiftUI
import UniformTypeIdentifiers

struct CanvasStudyView: View {
    let item: DownloadItem
    let analysis: MediaAnalysis?
    var fillsAvailableSpace: Bool = false
    
    @StateObject private var viewModel: CanvasViewModel
    @State private var newBoardTitle = ""
    @State private var showNewBoardAlert = false
    
    init(item: DownloadItem, analysis: MediaAnalysis?, fillsAvailableSpace: Bool = false) {
        self.item = item
        self.analysis = analysis
        self.fillsAvailableSpace = fillsAvailableSpace
        _viewModel = StateObject(wrappedValue: CanvasViewModel(
            downloadId: item.id,
            mediaTitle: item.displayTitle
        ))
    }
    
    var body: some View {
        Group {
            if fillsAvailableSpace {
                GeometryReader { proxy in
                    canvasStack(totalHeight: proxy.size.height)
                }
            } else {
                canvasStack(totalHeight: 520)
            }
        }
        .task {
            await viewModel.loadBoards()
        }
        .onDisappear {
            Task { await viewModel.flushSave() }
        }
        .alert("New Board", isPresented: $showNewBoardAlert) {
            TextField("Board name", text: $newBoardTitle)
            Button("Cancel", role: .cancel) { newBoardTitle = "" }
            Button("Create") {
                let title = newBoardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    await viewModel.createBoard(title: title.isEmpty ? "New Board" : title)
                    newBoardTitle = ""
                }
            }
        }
    }
    
    private func canvasStack(totalHeight: CGFloat) -> some View {
        let chrome: CGFloat = 72
        let canvasHeight = max(240, totalHeight - chrome)
        
        return VStack(spacing: 0) {
            boardPicker
            toolbar
            canvasArea(height: canvasHeight)
        }
    }
    
    private var boardPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.boards) { board in
                    Button {
                        Task { await viewModel.selectBoard(board.id) }
                    } label: {
                        Text(board.title)
                            .font(.caption.weight(viewModel.selectedBoardId == board.id ? .semibold : .regular))
                            .foregroundStyle(
                                viewModel.selectedBoardId == board.id
                                    ? StudyPanelDesign.accent
                                    : Color.secondary
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(
                                        viewModel.selectedBoardId == board.id
                                            ? StudyPanelDesign.accent.opacity(0.14)
                                            : Color.primary.opacity(0.05)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    newBoardTitle = ""
                    showNewBoardAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Add board")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    private var toolbar: some View {
        HStack(spacing: 8) {
            Group {
                if viewModel.isSaving {
                    ProgressView().controlSize(.mini)
                    Text("Saving")
                } else if let status = viewModel.statusMessage {
                    Text(status)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            
            Spacer(minLength: 0)
            
            if analysis != nil {
                Button {
                    if let analysis {
                        viewModel.importFromStudyPack(analysis)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Import study pack")
            }
            
            Button { viewModel.saveNow() } label: {
                Image(systemName: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderless)
            .help("Save")
            
            Menu {
                Button("Export PNG") { viewModel.exportPNG() }
                Button("Export .excalidraw") { viewModel.exportExcalidrawFile() }
                Button("Share…") { viewModel.shareExport() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Export & share")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
    
    private func canvasArea(height: CGFloat) -> some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.regular)
            } else {
                ExcalidrawWebView(
                    onMessage: { viewModel.handleBridgeMessage($0) },
                    onCoordinatorReady: { viewModel.bindBridge($0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                    viewModel.handleDrop(providers: providers)
                    return true
                }
            }
            
            if let error = viewModel.exportError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.94))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: StudyPanelDesign.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StudyPanelDesign.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
    
    private func boardThumbnailURL(_ board: CanvasBoard) -> URL? {
        let url = PathUtils.canvasThumbnailFile(board.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
