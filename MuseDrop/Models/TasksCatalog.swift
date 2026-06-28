//
//  TasksCatalog.swift
//  MuseDrop
//
//  A controlled vocabulary of research tasks — Papers-with-Code's "Tasks"
//  taxonomy: what a paper is *trying to do* (Image Classification, Question
//  Answering, Automatic Speech Recognition…), grouped by area. Detected in a
//  paper's title + abstract so Tasks are canonical, not free-form text.
//

import Foundation

enum TaskArea: String, Sendable, CaseIterable {
    case general = "General"
    case vision = "Vision"
    case video = "Video"
    case language = "Language"
    case audio = "Audio"
    case other = "Other"

    var order: Int {
        switch self {
        case .general: return 0
        case .vision: return 1
        case .video: return 2
        case .language: return 3
        case .audio: return 4
        case .other: return 5
        }
    }
}

struct CatalogTask: Identifiable, Hashable, Sendable {
    let name: String
    let area: TaskArea
    var aliases: [String] = []
    var id: String { name }
}

enum TasksCatalog {

    static let all: [CatalogTask] = [
        // MARK: General
        CatalogTask(name: "Agents", area: .general, aliases: ["agent", "agentic"]),
        CatalogTask(name: "Anomaly Detection", area: .general),
        CatalogTask(name: "Autonomous Driving", area: .general),
        CatalogTask(name: "Coding Agents", area: .general, aliases: ["code agent", "coding agent"]),
        CatalogTask(name: "Computer Use Agents", area: .general, aliases: ["computer use agent"]),
        CatalogTask(name: "Deepfake And Forensics", area: .general, aliases: ["deepfake"]),
        CatalogTask(name: "Document Understanding", area: .general),
        CatalogTask(name: "Embedding Models", area: .general, aliases: ["text embedding"]),
        CatalogTask(name: "Language Modeling", area: .general, aliases: ["language model"]),
        CatalogTask(name: "OCR", area: .general, aliases: ["optical character recognition"]),
        CatalogTask(name: "Omni Models", area: .general, aliases: ["omni-modal"]),
        CatalogTask(name: "Reasoning", area: .general),
        CatalogTask(name: "Reinforcement Learning", area: .general, aliases: ["RL"]),
        CatalogTask(name: "Remote Sensing", area: .general),
        CatalogTask(name: "Robotics", area: .general, aliases: ["robotic", "robot"]),
        CatalogTask(name: "Scene Text Recognition", area: .general),
        CatalogTask(name: "World Models", area: .general, aliases: ["world model"]),

        // MARK: Vision
        CatalogTask(name: "3D Generation", area: .vision),
        CatalogTask(name: "3D Instance Segmentation", area: .vision),
        CatalogTask(name: "3D Object Detection", area: .vision),
        CatalogTask(name: "3D Semantic Segmentation", area: .vision),
        CatalogTask(name: "3D Understanding", area: .vision),
        CatalogTask(name: "Depth Estimation", area: .vision),
        CatalogTask(name: "Document Layout Analysis", area: .vision),
        CatalogTask(name: "Earth Observation", area: .vision),
        CatalogTask(name: "Face Recognition", area: .vision),
        CatalogTask(name: "Face Verification", area: .vision),
        CatalogTask(name: "Image Classification", area: .vision),
        CatalogTask(name: "Image Editing", area: .vision),
        CatalogTask(name: "Image Generation", area: .vision, aliases: ["text-to-image", "text to image"]),
        CatalogTask(name: "Image Inpainting", area: .vision, aliases: ["inpainting"]),
        CatalogTask(name: "Image Matching", area: .vision),
        CatalogTask(name: "Image Matting", area: .vision),
        CatalogTask(name: "Image Restoration", area: .vision),
        CatalogTask(name: "Image Segmentation", area: .vision),
        CatalogTask(name: "Image Super-Resolution", area: .vision, aliases: ["super-resolution", "super resolution"]),
        CatalogTask(name: "Image Understanding", area: .vision),
        CatalogTask(name: "Medical Imaging", area: .vision),
        CatalogTask(name: "Motion Generation", area: .vision),
        CatalogTask(name: "Object Counting", area: .vision),
        CatalogTask(name: "Object Detection", area: .vision),
        CatalogTask(name: "Optical Flow", area: .vision),
        CatalogTask(name: "Pose Estimation", area: .vision),
        CatalogTask(name: "Semi-Supervised Image Classification", area: .vision),
        CatalogTask(name: "Stereo Matching", area: .vision),
        CatalogTask(name: "Zero-Shot Segmentation", area: .vision),

        // MARK: Video
        CatalogTask(name: "Cross-View Object Correspondence", area: .video),
        CatalogTask(name: "Object Tracking", area: .video, aliases: ["multi-object tracking"]),
        CatalogTask(name: "Video Classification", area: .video),
        CatalogTask(name: "Video Generation", area: .video, aliases: ["text-to-video", "text to video"]),
        CatalogTask(name: "Video Matting", area: .video),
        CatalogTask(name: "Video Restoration", area: .video),
        CatalogTask(name: "Video Segmentation", area: .video),
        CatalogTask(name: "Video Super-Resolution", area: .video),
        CatalogTask(name: "Video Understanding", area: .video),

        // MARK: Language
        CatalogTask(name: "Entity Typing", area: .language),
        CatalogTask(name: "Machine Translation", area: .language),
        CatalogTask(name: "Named Entity Recognition", area: .language, aliases: ["NER"]),
        CatalogTask(name: "Part-Of-Speech Tagging", area: .language, aliases: ["POS tagging"]),
        CatalogTask(name: "Question Answering", area: .language, aliases: ["question-answering"]),
        CatalogTask(name: "Relation Extraction", area: .language),
        CatalogTask(name: "Summarization", area: .language, aliases: ["summarisation"]),
        CatalogTask(name: "Table Question Answering", area: .language),
        CatalogTask(name: "Text Classification", area: .language),
        CatalogTask(name: "Text-to-SQL", area: .language, aliases: ["text to sql"]),

        // MARK: Audio
        CatalogTask(name: "Audio Classification", area: .audio),
        CatalogTask(name: "Audio Generation", area: .audio),
        CatalogTask(name: "Audio Understanding", area: .audio),
        CatalogTask(name: "Automatic Speech Recognition", area: .audio, aliases: ["ASR", "speech recognition"]),
        CatalogTask(name: "Text-To-Speech", area: .audio, aliases: ["TTS", "speech synthesis"]),
        CatalogTask(name: "Voice Cloning", area: .audio),

        // MARK: Other
        CatalogTask(name: "Biology", area: .other),
        CatalogTask(name: "Tabular Learning", area: .other),
        CatalogTask(name: "Time-Series Classification", area: .other),
        CatalogTask(name: "Time-Series Forecasting", area: .other, aliases: ["time series forecasting"]),
    ]

    /// Detect catalog tasks in `text`. Most specific (longest-named) win the cap,
    /// then grouped by area for display.
    static func detect(in text: String, limit: Int = 6) -> [CatalogTask] {
        let matched = all.filter { task in
            ([task.name] + task.aliases).contains { CatalogText.mentions(text, $0) }
        }
        let top = matched.sorted { $0.name.count > $1.name.count }.prefix(limit)
        return top.sorted {
            $0.area.order != $1.area.order ? $0.area.order < $1.area.order : $0.name < $1.name
        }
    }
}
