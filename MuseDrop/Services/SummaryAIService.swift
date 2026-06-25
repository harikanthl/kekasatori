//
//  SummaryAIService.swift
//  MuseDrop
//
//  Legacy entry point — delegates to MediaAIService.
//

import Foundation

class SummaryAIService {
    static let shared = SummaryAIService()
    
    private let mediaAI = MediaAIService.shared
    
    private init() {}
    
    func generateSummary(for mediaURL: URL) async throws -> SummaryResult {
        try await mediaAI.generateSummary(for: mediaURL)
    }
}

enum SummaryError: LocalizedError {
    case ffmpegNotFound
    case audioExtractionFailed(String)
    case speechRecognitionUnavailable
    case transcriptionFailed
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Please ensure ffmpeg is installed."
        case .audioExtractionFailed(let message):
            return "Failed to extract audio: \(message)"
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device."
        case .transcriptionFailed:
            return "Failed to transcribe audio."
        }
    }
}
