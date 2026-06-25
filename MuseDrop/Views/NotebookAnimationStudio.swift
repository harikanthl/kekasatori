//
//  NotebookAnimationStudio.swift
//  MuseDrop
//

import SwiftUI
import AVKit

struct NotebookAnimationStudio: View {
    @ObservedObject var viewModel: NotebookAnimationViewModel
    let onClose: () -> Void
    var onRendered: ((NotebookAnimationRecord) -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            studioHeader
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    environmentBanner
                    formulaSection
                    sceneTypeSection
                    styleSection
                    qualitySection
                    renderSection
                    
                    if !viewModel.animations.isEmpty {
                        gallerySection
                    }
                }
                .padding(20)
            }
            
            if viewModel.previewPlayer != nil {
                Divider()
                previewBar
            }
        }
        .frame(minWidth: 420, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.refreshEnvironment()
            viewModel.loadAnimations()
        }
        .onDisappear {
            viewModel.stopPreview()
        }
    }
    
    private var studioHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.12, blue: 0.22),
                                Color(red: 0.08, green: 0.14, blue: 0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "function")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Math Animation Studio")
                    .font(.headline)
                Text("Powered by Manim Community Edition")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    @ViewBuilder
    private var environmentBanner: some View {
        if let status = viewModel.environmentStatus {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status.isReady ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.statusMessage)
                        .font(.subheadline.weight(.medium))
                    if !status.isReady {
                        Text(status.installHint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
    }
    
    private var formulaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("LaTeX formula", systemImage: "sum")
                .font(.subheadline.weight(.semibold))
            
            Text("Paste or select math from your notebook. Use $...$ or $$...$$, or raw LaTeX.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            TextEditor(text: $viewModel.latexInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 88, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                }
                .foregroundStyle(Color(red: 0.92, green: 0.94, blue: 1.0))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                }
        }
    }
    
    private var sceneTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scene type", systemImage: "theatermasks")
                .font(.subheadline.weight(.semibold))
            
            Text("ML papers, quantum physics, astrophysics, chemistry — pick a visualization or let Auto detect.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ForEach(sceneCategories, id: \.self) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ManimSceneType.allCases.filter { $0.category == category }) { sceneType in
                            sceneTypeChip(sceneType)
                        }
                    }
                }
            }
            
            if let hint = sceneHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    private var sceneCategories: [String] {
        ["Smart", "Machine Learning", "Chemistry", "Physics", "Astrophysics", "Mathematics"]
    }
    
    private var sceneHint: String? {
        let expr = MathFunctionParser.pythonExpression(from: viewModel.latexInput)
        let analysis = ManimConceptDetector.analyze(latex: viewModel.latexInput)
        switch viewModel.selectedSceneType {
        case .auto:
            if let suggested = analysis.suggestedScene {
                return "Auto detected \(suggested.title) — \(suggested.subtitle)"
            }
            if let expr {
                return "Auto will build an equation + graph scene for `\(expr)`."
            }
            return "Auto picks attention, neural nets, quantum, orbits, waves, atoms, matrices, derivations, or graphs."
        case .attention:
            return #"Try: \text{Attention}(Q,K,V)=\mathrm{softmax}\!\left(\frac{QK^\top}{\sqrt{d_k}}\right)V"#
        case .neuralNetwork:
            return "Use `neural network`, `y = \\sigma(Wx+b)`, or layer sizes like `3-5-4-2`."
        case .convolution:
            return "Mention `convolution`, `CNN`, or `kernel` — animates a filter sliding over a feature map."
        case .gradientDescent:
            return "3D loss landscape with SGD path — uses Manim ThreeDScene (OpenGL)."
        case .matrixOps:
            return "Paste matrices like `[[1,2],[3,4]] × [[2,1],[0,3]]` or use \\begin{bmatrix}...\\end{bmatrix}."
        case .atomModel:
            return "Use Bohr energy levels (`E_n = -R_H/n^2`) or element symbols like H, C, O, Fe."
        case .quantumWave:
            return "Schrödinger / `\\psi` / `\\hbar` — particle-in-a-box or Gaussian wavepacket."
        case .wavePhysics:
            return "Traveling wave `E_0\\sin(kx-\\omega t)` — wavelength, frequency, amplitude."
        case .fourierSeries:
            return "Fourier sum of harmonics approaching a square wave — mention `fourier` or `harmonic`."
        case .orbitalMechanics:
            return "Kepler orbits — `F = G m_1 m_2 / r^2`, planet, ellipse, solar system."
        case .spacetime:
            return "General relativity — `G_{\\mu\\nu}`, spacetime curvature, black hole, geodesic."
        case .functionGraph:
            if let expr {
                return "Will plot `\(expr)` with axes and a moving point."
            }
            return "Tip: try `y = x^2`, `\\sin(x)`, or `x^3 - 2x` for a plottable function."
        case .equationGraph:
            return "Shows your formula with a live graph underneath."
        case .derivation:
            return "Use multiple steps separated by `\\to` or new lines, e.g. `(a+b)^2 \\to a^2+2ab+b^2`."
        case .formula:
            return "Classic LaTeX reveal with variable colors when detected."
        }
    }
    
    private func sceneTypeChip(_ sceneType: ManimSceneType) -> some View {
        let selected = viewModel.selectedSceneType == sceneType
        return Button {
            viewModel.selectedSceneType = sceneType
        } label: {
            HStack(spacing: 8) {
                Image(systemName: sceneType.icon)
                    .font(.caption.weight(.semibold))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sceneType.title)
                        .font(.caption.weight(.semibold))
                    Text(sceneType.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? StudyPanelDesign.accent.opacity(0.14) : Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? StudyPanelDesign.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Motion style", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            
            Text("Used for formula-only scenes or as emphasis in combined scenes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ManimAnimationStyle.allCases) { style in
                    styleChip(style)
                }
            }
        }
    }
    
    private func styleChip(_ style: ManimAnimationStyle) -> some View {
        let selected = viewModel.selectedStyle == style
        return Button {
            viewModel.selectedStyle = style
        } label: {
            HStack(spacing: 8) {
                Image(systemName: style.icon)
                    .font(.caption.weight(.semibold))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title)
                        .font(.caption.weight(.semibold))
                    Text(style.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? StudyPanelDesign.accent.opacity(0.14) : Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? StudyPanelDesign.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quality", systemImage: "film")
                .font(.subheadline.weight(.semibold))
            
            Picker("Quality", selection: $viewModel.selectedQuality) {
                ForEach(ManimRenderQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var renderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task {
                    if let record = await viewModel.render() {
                        onRendered?(record)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRendering {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(viewModel.isRendering ? "Rendering…" : "Render Animation")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudyPanelDesign.accent)
            .disabled(viewModel.isRendering || viewModel.latexInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            if let progress = viewModel.renderProgressMessage {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Today’s animations", systemImage: "film.stack")
                .font(.subheadline.weight(.semibold))
            
            ForEach(viewModel.animations) { record in
                animationRow(record)
            }
        }
    }
    
    private func animationRow(_ record: NotebookAnimationRecord) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 56, height: 36)
                .overlay {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(StudyPanelDesign.accent)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(record.latex)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("\(record.style.title) · \(record.quality.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                viewModel.play(record)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            
            Button {
                viewModel.revealInFinder(record)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            
            Button(role: .destructive) {
                Task { await viewModel.delete(record) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }
    
    private var previewBar: some View {
        VStack(spacing: 8) {
            if let player = viewModel.previewPlayer {
                VideoPlayer(player: player)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            
            HStack {
                if let record = viewModel.previewRecord {
                    Text(record.latex)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop") {
                    viewModel.stopPreview()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
    }
}
