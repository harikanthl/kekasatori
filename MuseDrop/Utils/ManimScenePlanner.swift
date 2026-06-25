//
//  ManimScenePlanner.swift
//  MuseDrop
//

import Foundation

struct ManimSceneJobPayload: Encodable, Sendable {
    let latex: String
    let scene_type: String
    let style: String
    let transform_to: String?
    let title: String?
    let background: String
    let function_expr: String?
    let x_min: Double
    let x_max: Double
    let y_min: Double
    let y_max: Double
    let steps: [String]
    let color_variables: [String]
    let matrix_a: [[Double]]
    let matrix_b: [[Double]]
    let attention_tokens: [String]
    let element_symbol: String
    let atomic_number: Int
    let neural_layers: [Int]
    let convolution_kernel_size: Int
    let learning_rate: Double
    let quantum_mode: String
    let fourier_terms: Int
    let orbital_eccentricity: Double
}

enum ManimScenePlanner {
    static func buildJob(
        latex: String,
        sceneType: ManimSceneType,
        style: ManimAnimationStyle,
        title: String?
    ) -> ManimSceneJobPayload {
        let cleaned = cleanLatex(latex)
        let analysis = ManimConceptDetector.analyze(latex: cleaned, contextTitle: title)
        let steps = derivationSteps(from: cleaned)
        let functionExpr = MathFunctionParser.pythonExpression(from: cleaned)
        let resolvedType = resolveSceneType(
            sceneType,
            analysis: analysis,
            steps: steps,
            functionExpr: functionExpr
        )
        
        var transformTo: String?
        if style == .transform {
            transformTo = splitTransformTarget(from: cleaned)
        }
        
        let range = suggestedRange(for: functionExpr)
        
        return ManimSceneJobPayload(
            latex: normalizedLatex(cleaned, forTransform: style == .transform, scene: resolvedType),
            scene_type: resolvedType.manimKey,
            style: style.rawValue,
            transform_to: transformTo,
            title: title,
            background: "#0d1117",
            function_expr: functionExpr,
            x_min: range.xMin,
            x_max: range.xMax,
            y_min: range.yMin,
            y_max: range.yMax,
            steps: steps,
            color_variables: isolatedVariables(from: cleaned),
            matrix_a: analysis.matrixA,
            matrix_b: analysis.matrixB,
            attention_tokens: analysis.attentionTokens,
            element_symbol: analysis.elementSymbol,
            atomic_number: analysis.atomicNumber,
            neural_layers: analysis.neuralLayers,
            convolution_kernel_size: analysis.convolutionKernelSize,
            learning_rate: analysis.learningRate,
            quantum_mode: analysis.quantumMode,
            fourier_terms: analysis.fourierTerms,
            orbital_eccentricity: analysis.orbitalEccentricity
        )
    }
    
    // MARK: - Private
    
    private struct PlotRange {
        let xMin: Double
        let xMax: Double
        let yMin: Double
        let yMax: Double
    }
    
    private static func resolveSceneType(
        _ type: ManimSceneType,
        analysis: ManimConceptDetector.Analysis,
        steps: [String],
        functionExpr: String?
    ) -> ManimSceneType {
        if type != .auto { return type }
        if let suggested = analysis.suggestedScene { return suggested }
        if steps.count >= 2 { return .derivation }
        if functionExpr != nil { return .equationGraph }
        return .formula
    }
    
    private static func normalizedLatex(
        _ latex: String,
        forTransform: Bool,
        scene: ManimSceneType
    ) -> String {
        switch scene {
        case .attention where !latex.lowercased().contains("attention"):
            return #"\\text{Attention}(Q,K,V)=\\mathrm{softmax}\\!\\left(\\frac{QK^\\top}{\\sqrt{d_k}}\\right)V"#
        case .neuralNetwork where !latex.lowercased().contains("sigma"):
            return #"y = \\sigma(Wx + b)"#
        case .convolution where !latex.lowercased().contains("conv"):
            return #"(I * K)(i,j) = \\sum_m \\sum_n I(i+m,j+n)\\,K(m,n)"#
        case .gradientDescent where !latex.contains("\\nabla"):
            return #"\\theta_{t+1} = \\theta_t - \\eta \\nabla_\\theta \\mathcal{L}(\\theta)"#
        case .quantumWave where !latex.contains("\\psi"):
            return #"-\\frac{\\hbar^2}{2m}\\frac{d^2\\psi}{dx^2} + V\\psi = i\\hbar\\frac{\\partial\\psi}{\\partial t}"#
        case .wavePhysics where !latex.contains("sin"):
            return #"E(x,t) = E_0\\sin(kx - \\omega t)"#
        case .fourierSeries where !latex.contains("\\sum"):
            return #"f(x)=\\sum_{n=1}^{\\infty}\\frac{\\sin((2n-1)x)}{2n-1}"#
        case .orbitalMechanics where !latex.lowercased().contains("f"):
            return #"F = G\\frac{m_1 m_2}{r^2}"#
        case .spacetime where !latex.contains("R"):
            return #"G_{\\mu\\nu} + \\Lambda g_{\\mu\\nu} = \\frac{8\\pi G}{c^4}T_{\\mu\\nu}"#
        default:
            break
        }
        
        if forTransform, let range = latex.range(of: "->") ?? latex.range(of: "\\to") {
            return String(latex[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return latex
    }
    
    private static func cleanLatex(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("$$"), value.hasSuffix("$$"), value.count > 4 {
            value = String(value.dropFirst(2).dropLast(2))
        } else if value.hasPrefix("$"), value.hasSuffix("$"), value.count > 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func derivationSteps(from latex: String) -> [String] {
        let separators = ["\\\\", "\n", "\\to", "\\rightarrow", "->", "→"]
        var parts = [latex]
        for separator in separators {
            if latex.contains(separator) {
                parts = latex
                    .components(separatedBy: separator)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if parts.count >= 2 { break }
            }
        }
        return parts.count >= 2 ? parts : []
    }
    
    private static func splitTransformTarget(from latex: String) -> String? {
        let separators = ["\\to", "\\rightarrow", "->", "→"]
        for separator in separators {
            guard let range = latex.range(of: separator) else { continue }
            let rhs = String(latex[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rhs.isEmpty { return rhs }
        }
        return nil
    }
    
    private static func isolatedVariables(from latex: String) -> [String] {
        let candidates = ["Q", "K", "V", "x", "y", "t", "E", "m", "c", "a", "b", "n", "k", "d", "W", "L", "G"]
        return candidates.filter { latex.contains($0) }
    }
    
    private static func suggestedRange(for functionExpr: String?) -> PlotRange {
        guard let functionExpr else {
            return PlotRange(xMin: -3, xMax: 3, yMin: -2, yMax: 8)
        }
        if functionExpr.contains("sin") || functionExpr.contains("cos") {
            return PlotRange(xMin: -6.28, xMax: 6.28, yMin: -1.5, yMax: 1.5)
        }
        if functionExpr.contains("x**3") {
            return PlotRange(xMin: -2, xMax: 2, yMin: -8, yMax: 8)
        }
        return PlotRange(xMin: -3, xMax: 3, yMin: -1, yMax: 9)
    }
}

enum MathFunctionParser {
    static func pythonExpression(from latex: String) -> String? {
        var expr = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let eqIndex = expr.firstIndex(of: "=") {
            let lhs = expr[..<eqIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = expr[expr.index(after: eqIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if lhs.contains("x") || lhs.contains("f") || lhs.contains("y") {
                expr = String(rhs)
            }
        }
        
        expr = expr
            .replacingOccurrences(of: "\\sin", with: "sin")
            .replacingOccurrences(of: "\\cos", with: "cos")
            .replacingOccurrences(of: "\\tan", with: "tan")
            .replacingOccurrences(of: "\\sqrt{", with: "sqrt(")
            .replacingOccurrences(of: "\\frac{", with: "(")
            .replacingOccurrences(of: "}{", with: ")/(")
            .replacingOccurrences(of: "}", with: ")")
            .replacingOccurrences(of: "{", with: "(")
            .replacingOccurrences(of: "\\cdot", with: "*")
            .replacingOccurrences(of: "\\times", with: "*")
            .replacingOccurrences(of: "\\left", with: "")
            .replacingOccurrences(of: "\\right", with: "")
            .replacingOccurrences(of: "^", with: "**")
        
        guard expr.contains("x"), isSafeExpression(expr) else { return nil }
        
        expr = expr
            .replacingOccurrences(of: "sin(", with: "np.sin(")
            .replacingOccurrences(of: "cos(", with: "np.cos(")
            .replacingOccurrences(of: "tan(", with: "np.tan(")
            .replacingOccurrences(of: "sqrt(", with: "np.sqrt(")
            .replacingOccurrences(of: "pi", with: "np.pi")
        
        return expr
    }
    
    private static func isSafeExpression(_ expr: String) -> Bool {
        // Explicit denylist for tokens that could enable attribute/subscript
        // access (defense-in-depth alongside the Python-side eval guard).
        let forbidden: [Character] = ["_", "[", "]"]
        if expr.contains(where: { forbidden.contains($0) }) { return false }

        let allowed = CharacterSet(charactersIn: "x0123456789.+-*/()**, npisqrtcostan ")
        return expr.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
