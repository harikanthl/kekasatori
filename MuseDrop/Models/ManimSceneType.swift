//
//  ManimSceneType.swift
//  MuseDrop
//

import Foundation

enum ManimSceneType: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    // Machine learning & deep learning
    case attention
    case neuralNetwork
    case convolution
    case gradientDescent
    case matrixOps
    // Chemistry
    case atomModel
    // Physics & quantum
    case quantumWave
    case wavePhysics
    case fourierSeries
    // Astrophysics
    case orbitalMechanics
    case spacetime
    // Classic math
    case functionGraph
    case equationGraph
    case derivation
    case formula
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .auto: return "Auto Scene"
        case .attention: return "Attention"
        case .neuralNetwork: return "Neural Network"
        case .convolution: return "Convolution"
        case .gradientDescent: return "Gradient Descent"
        case .matrixOps: return "Matrix Multiply"
        case .atomModel: return "Atom Model"
        case .quantumWave: return "Quantum Wave"
        case .wavePhysics: return "Wave Physics"
        case .fourierSeries: return "Fourier Series"
        case .orbitalMechanics: return "Orbital Motion"
        case .spacetime: return "Spacetime"
        case .functionGraph: return "Function Graph"
        case .equationGraph: return "Equation + Graph"
        case .derivation: return "Step Derivation"
        case .formula: return "Formula Only"
        }
    }
    
    var subtitle: String {
        switch self {
        case .auto: return "Detects ML, physics, chemistry"
        case .attention: return "Q·K·V transformer attention"
        case .neuralNetwork: return "Feedforward layers + forward pass"
        case .convolution: return "CNN filter sliding over grid"
        case .gradientDescent: return "3D loss surface + descent path"
        case .matrixOps: return "Animated matrix product"
        case .atomModel: return "Bohr atom with orbiting electrons"
        case .quantumWave: return "3D wavefunction landscape"
        case .wavePhysics: return "Traveling sine wave"
        case .fourierSeries: return "Harmonics building a signal"
        case .orbitalMechanics: return "3D Kepler ellipse orbit"
        case .spacetime: return "3D curved spacetime grid"
        case .functionGraph: return "Axes, curve, moving point"
        case .equationGraph: return "Formula with live plot"
        case .derivation: return "Transform between steps"
        case .formula: return "Typeset LaTeX reveal"
        }
    }
    
    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .attention: return "brain.head.profile"
        case .neuralNetwork: return "point.3.connected.trianglepath.dotted"
        case .convolution: return "square.grid.2x2"
        case .gradientDescent: return "arrow.down.right.circle"
        case .matrixOps: return "square.grid.3x3"
        case .atomModel: return "atom"
        case .quantumWave: return "waveform.path.ecg"
        case .wavePhysics: return "water.waves"
        case .fourierSeries: return "waveform"
        case .orbitalMechanics: return "moon.stars"
        case .spacetime: return "globe.americas"
        case .functionGraph: return "chart.xyaxis.line"
        case .equationGraph: return "function"
        case .derivation: return "arrow.triangle.swap"
        case .formula: return "sum"
        }
    }
    
    var manimKey: String {
        switch self {
        case .auto: return "auto"
        case .attention: return "attention"
        case .neuralNetwork: return "neural_network"
        case .convolution: return "convolution"
        case .gradientDescent: return "gradient_descent"
        case .matrixOps: return "matrix_ops"
        case .atomModel: return "atom_model"
        case .quantumWave: return "quantum_wave"
        case .wavePhysics: return "wave_physics"
        case .fourierSeries: return "fourier_series"
        case .orbitalMechanics: return "orbital_mechanics"
        case .spacetime: return "spacetime"
        case .functionGraph: return "function_graph"
        case .equationGraph: return "equation_graph"
        case .derivation: return "derivation"
        case .formula: return "formula"
        }
    }
    
    /// Grouped for UI section headers in the animation studio.
    var category: String {
        switch self {
        case .auto: return "Smart"
        case .attention, .neuralNetwork, .convolution, .gradientDescent, .matrixOps:
            return "Machine Learning"
        case .atomModel: return "Chemistry"
        case .quantumWave, .wavePhysics, .fourierSeries: return "Physics"
        case .orbitalMechanics, .spacetime: return "Astrophysics"
        case .functionGraph, .equationGraph, .derivation, .formula: return "Mathematics"
        }
    }
    
    /// Renders with Manim `ThreeDScene` (OpenGL) for depth, surfaces, and camera motion.
    var usesThreeDScene: Bool {
        switch self {
        case .gradientDescent, .spacetime, .orbitalMechanics, .quantumWave:
            return true
        default:
            return false
        }
    }
    
    var manimSceneClass: String {
        usesThreeDScene ? "MuseDrop3DScene" : "MuseDropFormulaScene"
    }
}
