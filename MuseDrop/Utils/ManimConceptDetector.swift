//
//  ManimConceptDetector.swift
//  MuseDrop
//

import Foundation

enum ManimConceptDetector {
    struct Analysis: Sendable {
        let suggestedScene: ManimSceneType?
        let attentionTokens: [String]
        let matrixA: [[Double]]
        let matrixB: [[Double]]
        let elementSymbol: String
        let atomicNumber: Int
        let neuralLayers: [Int]
        let convolutionKernelSize: Int
        let learningRate: Double
        let quantumMode: String
        let fourierTerms: Int
        let orbitalEccentricity: Double
    }
    
    static func analyze(latex: String, contextTitle: String? = nil) -> Analysis {
        let combined = "\(latex) \(contextTitle ?? "")".lowercased()
        
        return Analysis(
            suggestedScene: suggestScene(from: combined, latex: latex),
            attentionTokens: attentionTokens(from: combined),
            matrixA: parseMatrix(from: latex, fallback: [[1, 2], [3, 4]]),
            matrixB: parseMatrixB(from: latex, fallback: [[2, 1], [0, 3]]),
            elementSymbol: elementSymbol(from: combined, latex: latex),
            atomicNumber: atomicNumber(from: combined, latex: latex),
            neuralLayers: neuralLayers(from: combined, latex: latex),
            convolutionKernelSize: convolutionKernelSize(from: combined),
            learningRate: learningRate(from: combined, latex: latex),
            quantumMode: quantumMode(from: combined, latex: latex),
            fourierTerms: fourierTerms(from: combined),
            orbitalEccentricity: orbitalEccentricity(from: combined)
        )
    }
    
    // MARK: - Scene suggestion (priority order)
    
    private static func suggestScene(from combined: String, latex: String) -> ManimSceneType? {
        if isAttentionContent(combined) { return .attention }
        if isSpacetimeContent(combined) { return .spacetime }
        if isOrbitalContent(combined) { return .orbitalMechanics }
        if isQuantumContent(combined, latex: latex) { return .quantumWave }
        if isConvolutionContent(combined, latex: latex) { return .convolution }
        if isNeuralNetworkContent(combined, latex: latex) { return .neuralNetwork }
        if isGradientDescentContent(combined, latex: latex) { return .gradientDescent }
        if isFourierContent(combined, latex: latex) { return .fourierSeries }
        if isWavePhysicsContent(combined, latex: latex) { return .wavePhysics }
        if isAtomContent(combined, latex: latex) { return .atomModel }
        if isMatrixContent(combined, latex: latex) { return .matrixOps }
        return nil
    }
    
    // MARK: - ML / DL
    
    static func isAttentionContent(_ text: String) -> Bool {
        let keywords = [
            "attention", "softmax", "transformer", "multi-head", "multihead",
            "query", "qkv", "qk^t", "qk^\\top", "d_k", "d_{k}", "self-attention",
            "all you need"
        ]
        return keywords.contains { text.contains($0) }
    }
    
    static func isNeuralNetworkContent(_ text: String, latex: String) -> Bool {
        let keywords = [
            "neural network", "feedforward", "perceptron", "mlp", "hidden layer",
            "backprop", "relu", "sigmoid", "activation", "deep learning",
            "fully connected", "dense layer"
        ]
        if keywords.contains(where: { text.contains($0) }) { return true }
        return latex.contains("\\sigma") && (latex.contains("W") || latex.contains("w"))
    }
    
    static func isConvolutionContent(_ text: String, latex: String) -> Bool {
        let keywords = ["convolution", "conv2d", "cnn", "kernel", "feature map", "pooling", "stride"]
        if keywords.contains(where: { text.contains($0) }) { return true }
        return latex.contains("*") && text.contains("filter")
    }
    
    static func isGradientDescentContent(_ text: String, latex: String) -> Bool {
        let keywords = [
            "gradient descent", "sgd", "adam", "optimizer", "loss function",
            "learning rate", "stochastic", "momentum", "backpropagation"
        ]
        if keywords.contains(where: { text.contains($0) }) { return true }
        return latex.contains("\\nabla") || latex.contains("\\partial")
    }
    
    static func isMatrixContent(_ text: String, latex: String) -> Bool {
        if text.contains("matrix") || text.contains("matmul") || text.contains("×") {
            return true
        }
        if latex.contains("\\begin{matrix}") || latex.contains("\\begin{bmatrix}") {
            return true
        }
        if latex.contains("[[") && latex.contains("]]") {
            return true
        }
        let matrixVars = ["\\mathbf{w}", "W_q", "W_k", "W_v", "W_Q", "W_K", "W_V"]
        return matrixVars.contains { latex.contains($0) }
    }
    
    // MARK: - Chemistry
    
    static func isAtomContent(_ text: String, latex: String) -> Bool {
        let keywords = ["atom", "electron", "orbital", "bohr", "nucleus", "proton", "neutron", "shell"]
        if keywords.contains(where: { text.contains($0) }) { return true }
        if latex.contains("E_n") || latex.contains("R_H") {
            return true
        }
        return elementSymbol(from: text, latex: latex) != "H" || text.contains("atom")
    }
    
    // MARK: - Physics
    
    static func isQuantumContent(_ text: String, latex: String) -> Bool {
        let keywords = [
            "schrodinger", "schrödinger", "wavefunction", "wave function", "hamiltonian",
            "quantum", "eigenstate", "eigenvalue", "superposition", "tunneling"
        ]
        if keywords.contains(where: { text.contains($0) }) { return true }
        return latex.contains("\\psi") || latex.contains("hbar") || latex.contains("\\hbar")
    }
    
    static func isWavePhysicsContent(_ text: String, latex: String) -> Bool {
        let keywords = ["wavelength", "frequency", "standing wave", "electromagnetic", "amplitude"]
        if keywords.contains(where: { text.contains($0) }) { return true }
        if text.contains("wave") && !isQuantumContent(text, latex: latex) { return true }
        return latex.contains("k x") || latex.contains("kx") || latex.contains("\\omega")
    }
    
    static func isFourierContent(_ text: String, latex: String) -> Bool {
        let keywords = ["fourier", "harmonic", "spectrum", "fft", "frequency domain"]
        if keywords.contains(where: { text.contains($0) }) { return true }
        return latex.contains("\\sum") && (latex.contains("sin") || latex.contains("cos"))
    }
    
    // MARK: - Astrophysics
    
    static func isOrbitalContent(_ text: String) -> Bool {
        let keywords = [
            "kepler", "orbit", "planet", "gravity", "solar system", "ellipse",
            "newton", "gravitational", "celestial", "perihelion"
        ]
        return keywords.contains { text.contains($0) }
    }
    
    static func isSpacetimeContent(_ text: String) -> Bool {
        let keywords = [
            "spacetime", "space-time", "einstein", "relativity", "curvature",
            "black hole", "geodesic", "general relativity", "gravitational lens"
        ]
        return keywords.contains { text.contains($0) }
    }
    
    // MARK: - Parameter extraction
    
    private static func attentionTokens(from text: String) -> [String] {
        if text.contains("all you need") {
            return ["Attention", "is", "all", "you", "need"]
        }
        if text.contains("transformer") {
            return ["The", "cat", "sat", "on", "mat"]
        }
        return ["Q", "K", "V"]
    }
    
    private static func neuralLayers(from text: String, latex: String) -> [Int] {
        let pattern = #"(\d+)\s*[-x×]\s*(\d+)\s*[-x×]\s*(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: "\(text) \(latex)", range: NSRange("\(text) \(latex)".startIndex..., in: "\(text) \(latex)")) {
            let source = "\(text) \(latex)"
            var layers: [Int] = []
            for i in 1...3 {
                if let range = Range(match.range(at: i), in: source), let n = Int(source[range]) {
                    layers.append(n)
                }
            }
            if layers.count >= 3 { return layers }
        }
        if text.contains("deep") { return [4, 8, 8, 4, 2] }
        return [3, 5, 4, 2]
    }
    
    private static func convolutionKernelSize(from text: String) -> Int {
        if text.contains("5x5") || text.contains("5×5") { return 5 }
        if text.contains("7x7") || text.contains("7×7") { return 7 }
        return 3
    }
    
    private static func learningRate(from text: String, latex: String) -> Double {
        let combined = "\(text) \(latex)"
        let pattern = #"lr\s*[=:]\s*([0-9.]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)),
           let range = Range(match.range(at: 1), in: combined),
           let value = Double(combined[range]) {
            return value
        }
        if combined.contains("0.01") { return 0.01 }
        if combined.contains("0.001") { return 0.001 }
        return 0.1
    }
    
    private static func quantumMode(from text: String, latex: String) -> String {
        if text.contains("harmonic") || latex.contains("omega") { return "harmonic" }
        if text.contains("tunnel") || text.contains("barrier") { return "barrier" }
        if text.contains("free") || text.contains("gaussian") { return "gaussian" }
        return "box"
    }
    
    private static func fourierTerms(from text: String) -> Int {
        if text.contains("9 term") || text.contains("n=9") { return 9 }
        if text.contains("5 term") || text.contains("n=5") { return 5 }
        return 7
    }
    
    private static func orbitalEccentricity(from text: String) -> Double {
        if text.contains("circular") { return 0.0 }
        if text.contains("highly elliptical") { return 0.8 }
        return 0.45
    }
    
    // MARK: - Matrices
    
    private static func parseMatrix(from latex: String, fallback: [[Double]]) -> [[Double]] {
        if let matrix = parseBracketMatrix(latex) { return matrix }
        if let matrix = parseLatexMatrix(latex) { return matrix }
        return fallback
    }
    
    private static func parseMatrixB(from latex: String, fallback: [[Double]]) -> [[Double]] {
        let parts = latex.components(separatedBy: CharacterSet(charactersIn: "×x\\cdot"))
        if parts.count >= 2,
           let second = parseBracketMatrix(parts[1]) ?? parseLatexMatrix(parts[1]) {
            return second
        }
        return fallback
    }
    
    private static func parseBracketMatrix(_ text: String) -> [[Double]]? {
        guard let start = text.range(of: "[["),
              let end = text.range(of: "]]", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        let body = String(text[start.upperBound..<end.lowerBound])
        let rows = body.components(separatedBy: "],[")
        let matrix = rows.compactMap { row -> [Double]? in
            let cleaned = row.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            let values = cleaned.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return values.isEmpty ? nil : values
        }
        return matrix.count >= 2 ? matrix : nil
    }
    
    private static func parseLatexMatrix(_ text: String) -> [[Double]]? {
        guard let begin = text.range(of: "\\begin{"),
              let end = text.range(of: "\\end{", range: begin.upperBound..<text.endIndex) else {
            return nil
        }
        let body = String(text[begin.upperBound..<end.upperBound])
        let rows = body.components(separatedBy: "\\\\")
        let matrix = rows.compactMap { row -> [Double]? in
            let values = row.split(separator: "&").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return values.isEmpty ? nil : values
        }
        return matrix.count >= 2 ? matrix : nil
    }
    
    // MARK: - Chemistry
    
    private static func elementSymbol(from text: String, latex: String) -> String {
        let table: [(String, String)] = [
            ("uranium", "U"), ("gold", "Au"), ("silver", "Ag"), ("iron", "Fe"),
            ("carbon", "C"), ("oxygen", "O"), ("nitrogen", "N"), ("helium", "He"),
            ("hydrogen", "H"), ("sodium", "Na"), ("chlorine", "Cl")
        ]
        for (name, symbol) in table where text.contains(name) {
            return symbol
        }
        
        let pattern = #"\b([A-Z][a-z]?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: latex, range: NSRange(latex.startIndex..., in: latex)),
           let range = Range(match.range(at: 1), in: latex) {
            let symbol = String(latex[range])
            if symbol.count <= 2 { return symbol }
        }
        return "H"
    }
    
    private static func atomicNumber(from text: String, latex: String) -> Int {
        let symbol = elementSymbol(from: text, latex: latex)
        let numbers: [String: Int] = [
            "H": 1, "He": 2, "C": 6, "N": 7, "O": 8, "Na": 11, "Cl": 17,
            "Fe": 26, "Ag": 47, "Au": 79, "U": 92
        ]
        return numbers[symbol] ?? 1
    }
}
