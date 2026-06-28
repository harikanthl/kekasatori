//
//  SettingsViewModel.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var defaultAudioFormat: AudioFormat = .mp3
    @Published var defaultVideoResolution: VideoResolution = .best
    @Published var enableAISummary: Bool = true
    @Published var defaultHomeMode: ConsumptionMode = .download
    @Published var libraryLocation: URL
    
    private let userDefaults = UserDefaults.standard
    private static let defaultHomeModeKey = "defaultHomeMode"
    @Published var enableWebResearch: Bool = true
    @Published var manimExecutablePath: String = ""
    @Published var manimStatusMessage: String = "Checking…"
    @Published var manimIsReady = false
    
    private static let webResearchKey = "enableWebResearch"
    private static let manimPathKey = "manimExecutablePath"

    // MARK: - LLM / BYOK (Tutor)
    @Published var llmPreset: LLMProviderPreset = .openRouter
    @Published var llmModelId: String = LLMModelPreset.defaultOpenRouterModel
    @Published var llmBaseURL: String = ""
    @Published var llmPreferOnDevice: Bool = true
    @Published var llmEnableRAG: Bool = true
    /// Opt-in: analyse figures/charts/tables in papers via a vision-capable cloud model.
    @Published var llmAnalyzeFigures: Bool = false
    /// Write-only entry field; never pre-filled with the stored secret.
    @Published var llmAPIKeyInput: String = ""
    @Published var llmHasKey: Bool = false
    @Published var llmStatusMessage: String = ""
    
    enum AudioFormat: String, CaseIterable {
        case mp3 = "MP3"
        case aac = "AAC"
        case wav = "WAV"
    }
    
    enum VideoResolution: String, CaseIterable {
        case best = "Best Available"
        case hd1080 = "1080p"
        case hd720 = "720p"
        case hd480 = "480p"
    }
    
    init() {
        libraryLocation = PathUtils.libraryDirectory
        
        // Load settings
        if let audioFormatString = userDefaults.string(forKey: "defaultAudioFormat"),
           let audioFormat = AudioFormat(rawValue: audioFormatString) {
            defaultAudioFormat = audioFormat
        }
        
        if let videoResolutionString = userDefaults.string(forKey: "defaultVideoResolution"),
           let videoResolution = VideoResolution(rawValue: videoResolutionString) {
            defaultVideoResolution = videoResolution
        }
        
        // Default ON when never set. Using `.bool(forKey:)` directly returns
        // false for an absent key, which then gets persisted by saveSettings()
        // and silently disables every AI study tool (and the Generate button).
        if userDefaults.object(forKey: "enableAISummary") != nil {
            enableAISummary = userDefaults.bool(forKey: "enableAISummary")
        }
        
        if let modeRaw = userDefaults.string(forKey: Self.defaultHomeModeKey),
           let mode = ConsumptionMode(rawValue: modeRaw) {
            defaultHomeMode = mode
        }
        
        if userDefaults.object(forKey: Self.webResearchKey) != nil {
            enableWebResearch = userDefaults.bool(forKey: Self.webResearchKey)
        }
        
        manimExecutablePath = userDefaults.string(forKey: Self.manimPathKey) ?? ""
        ManimEnvironment.setCustomExecutablePath(manimExecutablePath.isEmpty ? nil : manimExecutablePath)

        let llm = LLMProviderSettings.load()
        llmPreset = llm.preset
        llmModelId = llm.modelId
        llmBaseURL = llm.baseURL
        llmPreferOnDevice = llm.preferOnDevice
        llmEnableRAG = llm.enableRAG
        llmAnalyzeFigures = llm.analyzeFigures
        llmHasKey = KeychainService.has(KeychainService.Account.llmChat)
        refreshLLMStatus()
    }

    // MARK: - LLM settings

    var currentLLMSettings: LLMProviderSettings {
        LLMProviderSettings(
            preset: llmPreset,
            modelId: llmModelId,
            baseURL: llmBaseURL,
            preferOnDevice: llmPreferOnDevice,
            enableRAG: llmEnableRAG,
            analyzeFigures: llmAnalyzeFigures
        )
    }

    func saveLLMSettings() {
        currentLLMSettings.save()
        if !llmAPIKeyInput.trimmingCharacters(in: .whitespaces).isEmpty {
            KeychainService.set(llmAPIKeyInput.trimmingCharacters(in: .whitespaces),
                                for: KeychainService.Account.llmChat)
            llmAPIKeyInput = ""
        }
        llmHasKey = KeychainService.has(KeychainService.Account.llmChat)
        refreshLLMStatus()
    }

    func clearLLMKey() {
        KeychainService.delete(KeychainService.Account.llmChat)
        llmHasKey = false
        refreshLLMStatus()
    }

    func refreshLLMStatus() {
        llmStatusMessage = LLMRouter.shared.statusDescription(settings: currentLLMSettings)
    }
    
    func refreshManimStatus() async {
        let status = await ManimEnvironment.check()
        manimIsReady = status.isReady
        if status.isReady, let path = status.manimPath {
            manimStatusMessage = "Ready · \(path.path)"
        } else {
            manimStatusMessage = status.statusMessage
        }
    }
    
    func saveSettings() {
        userDefaults.set(defaultAudioFormat.rawValue, forKey: "defaultAudioFormat")
        userDefaults.set(defaultVideoResolution.rawValue, forKey: "defaultVideoResolution")
        userDefaults.set(enableAISummary, forKey: "enableAISummary")
        userDefaults.set(defaultHomeMode.rawValue, forKey: Self.defaultHomeModeKey)
        userDefaults.set(enableWebResearch, forKey: Self.webResearchKey)
        ManimEnvironment.setCustomExecutablePath(manimExecutablePath.isEmpty ? nil : manimExecutablePath)
        userDefaults.set(manimExecutablePath, forKey: Self.manimPathKey)
    }
    
    static var defaultHomeMode: ConsumptionMode {
        guard let raw = UserDefaults.standard.string(forKey: defaultHomeModeKey),
              let mode = ConsumptionMode(rawValue: raw) else {
            return .download
        }
        return mode
    }
    
    static var isAIEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableAISummary") as? Bool ?? true
    }
    
    static var isWebResearchEnabled: Bool {
        UserDefaults.standard.object(forKey: webResearchKey) as? Bool ?? true
    }
    
    func clearDownloadHistory() {
        LibraryManager.shared.downloads.removeAll()
        LibraryManager.shared.saveDownloads()
    }
    
    func clearLibrary() {
        let libraryManager = LibraryManager.shared
        let items = libraryManager.downloads
        Task {
            for item in items {
                await libraryManager.deleteCompletely(item)
            }
        }
    }
}

