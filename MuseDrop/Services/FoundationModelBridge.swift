//
//  FoundationModelBridge.swift
//  MuseDrop
//
//  Uses Apple's Foundation Models framework (macOS 26+) when available.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable(description: "Structured summary of spoken content")
struct GenerableSummary {
    @Guide(description: "Single sentence headline")
    var oneLine: String
    
    @Guide(description: "Short overview paragraph")
    var paragraph: String
    
    @Guide(description: "Key takeaway bullet points", .count(3...8))
    var bullets: [String]
}

@available(macOS 26.0, *)
@Generable(description: "Study notes section from a lecture")
struct GenerableNoteSection {
    @Guide(description: "Section heading")
    var heading: String
    
    @Guide(description: "Paragraph notes for this section")
    var content: String
    
    @Guide(description: "Bullet points", .count(0...6))
    var bullets: [String]
}

@available(macOS 26.0, *)
@Generable(description: "Organized study notes")
struct GenerableStudyNotes {
    @Guide(description: "Notes title")
    var title: String
    
    @Guide(description: "Ordered note sections", .count(2...16))
    var sections: [GenerableNoteSection]
}

@available(macOS 26.0, *)
@Generable(description: "Study note sections for one lecture segment")
struct GenerableNoteSectionPack {
    @Guide(description: "Detailed sections for this segment", .count(2...6))
    var sections: [GenerableNoteSection]
}

@available(macOS 26.0, *)
@Generable(description: "Flashcard for studying")
struct GenerableFlashCard {
    @Guide(description: "Question or term on front of card")
    var front: String
    
    @Guide(description: "Answer or definition on back of card")
    var back: String
    
    @Guide(description: "Topic tag")
    var tag: String
}

@available(macOS 26.0, *)
@Generable(description: "Important concept from lecture")
struct GenerableKeyConcept {
    @Guide(description: "Concept name or term")
    var term: String
    
    @Guide(description: "Clear definition")
    var definition: String
    
    @Guide(description: "Importance: high, medium, or low")
    var importance: String
}

@available(macOS 26.0, *)
@Generable(description: "Node in a concept mind map")
struct GenerableMindMapNode {
    @Guide(description: "Stable node id")
    var id: String
    
    @Guide(description: "Short label")
    var label: String
    
    @Guide(description: "Depth level: 0 center, 1 primary branch, 2 sub-topic", .range(0...2))
    var level: Int
}

@available(macOS 26.0, *)
@Generable(description: "Connection between mind map nodes")
struct GenerableMindMapEdge {
    @Guide(description: "Stable edge id")
    var id: String
    
    @Guide(description: "Source node id")
    var fromId: String
    
    @Guide(description: "Target node id")
    var toId: String
    
    @Guide(description: "Relationship label")
    var relationship: String
}

@available(macOS 26.0, *)
@Generable(description: "Concept graph / mind map")
struct GenerableMindMap {
    @Guide(description: "Central topic")
    var centralTopic: String
    
    @Guide(description: "All nodes including center", .count(3...20))
    var nodes: [GenerableMindMapNode]
    
    @Guide(description: "Edges connecting nodes", .count(2...20))
    var edges: [GenerableMindMapEdge]
}

@available(macOS 26.0, *)
@Generable(description: "Mind map fragment for one lecture segment")
struct GenerableMindMapSegment {
    @Guide(description: "Sub-topic label for this segment")
    var segmentTopic: String
    
    @Guide(description: "Nodes for this segment", .count(3...8))
    var nodes: [GenerableMindMapNode]
    
    @Guide(description: "Edges within this segment", .count(2...8))
    var edges: [GenerableMindMapEdge]
}

@available(macOS 26.0, *)
@Generable(description: "Key concepts from one lecture segment")
struct GenerableConceptSegmentPack {
    @Guide(description: "Important concepts from this segment", .count(2...6))
    var concepts: [GenerableKeyConcept]
}

@available(macOS 26.0, *)
@Generable(description: "Pack of flashcards")
struct GenerableFlashcardPack {
    @Guide(description: "Flashcards", .count(3...10))
    var cards: [GenerableFlashCard]
}

@available(macOS 26.0, *)
@Generable(description: "Pack of key concepts")
struct GenerableConceptPack {
    @Guide(description: "Important concepts", .count(3...14))
    var concepts: [GenerableKeyConcept]
}

@available(macOS 26.0, *)
@Generable(description: "Brief summary of one lecture section")
struct GenerableChunkSummary {
    @Guide(description: "Short summary paragraph for this section")
    var paragraph: String
    
    @Guide(description: "Key points from this section", .count(2...5))
    var bullets: [String]
}

@available(macOS 26.0, *)
struct FoundationModelAnalysisOptions {
    var forceRegenerate: Bool = false
    var researchContext: String?
    var enableWebResearchTool: Bool = false
}

@available(macOS 26.0, *)
struct WebResearchTool: Tool {
    let name = "webResearch"
    let description = "Search the public web for factual context about technical topics mentioned in the lecture."
    
    @Generable
    struct Arguments {
        @Guide(description: "Focused web search query, 3-10 words")
        var query: String
    }
    
    func call(arguments: Arguments) async throws -> String {
        let results = await WebSearchService.search(arguments.query, maxResults: 3)
        guard let formatted = WebSearchService.formatForPrompt(results) else {
            return "No web results found for \"\(arguments.query)\"."
        }
        return formatted
    }
}

@available(macOS 26.0, *)
enum FoundationModelBridge {
    typealias ProgressHandler = @Sendable (String) -> Void
    
    private static let logService = LogService.shared
    
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }
    
    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to use on-device AI."
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable:
            return "Apple Intelligence is unavailable right now."
        }
    }
    
    static func analyze(
        transcript: String,
        title: String,
        session: UUID,
        options: FoundationModelAnalysisOptions = FoundationModelAnalysisOptions(),
        onProgress: ProgressHandler? = nil
    ) async throws -> MediaAnalysisPayload {
        try await ensureActive(session)
        let normalized = AnalysisText.normalize(transcript)
        let scale = AnalysisText.StudyPackScale.from(transcript: normalized)
        let summaryTools: [any Tool] = options.enableWebResearchTool ? [WebResearchTool()] : []
        
        let regenerationNote = options.forceRegenerate
            ? "\nRegeneration: fresh wording and reorganized content."
            : ""
        let researchBlock = options.researchContext.map { "\n\n\($0)" } ?? ""
        let densityNote = densityInstruction(for: scale)
        
        onProgress?("Analyzing lecture (\(scale.chunkCount) segments, on-device AI)…")
        
        let summary = try await generateSummary(
            transcript: normalized,
            title: title,
            session: session,
            tools: summaryTools,
            options: options,
            regenerationNote: regenerationNote,
            researchBlock: researchBlock,
            onProgress: onProgress
        )
        
        try await ensureActive(session)
        onProgress?("Building study notes…")
        let notes = try await generateNotes(
            transcript: normalized,
            title: title,
            summary: summary,
            session: session,
            scale: scale,
            tools: [],
            options: options,
            regenerationNote: regenerationNote,
            researchBlock: researchBlock,
            densityNote: densityNote,
            onProgress: onProgress
        )
        
        try await ensureActive(session)
        onProgress?("Creating flashcards…")
        let cards = try await generateFlashcards(
            transcript: normalized,
            title: title,
            summary: summary,
            session: session,
            scale: scale,
            options: options,
            regenerationNote: regenerationNote,
            researchBlock: researchBlock,
            densityNote: densityNote,
            onProgress: onProgress
        )
        
        try await ensureActive(session)
        onProgress?("Extracting key concepts…")
        let concepts = try await generateConcepts(
            transcript: normalized,
            title: title,
            summary: summary,
            session: session,
            scale: scale,
            options: options,
            regenerationNote: regenerationNote,
            researchBlock: researchBlock,
            densityNote: densityNote,
            onProgress: onProgress
        )
        
        try await ensureActive(session)
        onProgress?("Building concept map…")
        let mindMap = try await generateMindMap(
            transcript: normalized,
            title: title,
            summary: summary,
            session: session,
            scale: scale,
            options: options,
            regenerationNote: regenerationNote,
            researchBlock: researchBlock,
            densityNote: densityNote,
            onProgress: onProgress
        )
        
        return MediaAnalysisPayload(
            summary: SummaryResult.from(
                oneLine: summary.oneLine,
                paragraph: summary.paragraph,
                bullets: summary.bullets
            ),
            notes: StudyNotes(
                title: notes.title,
                sections: notes.sections.map {
                    NoteSection(heading: $0.heading, content: $0.content, bullets: $0.bullets)
                }
            ),
            keyConcepts: concepts,
            flashcards: cards,
            mindMap: mindMap,
            engine: .foundationModels
        )
    }
    
    // MARK: - Context window management (TN3193)
    
    private static func ensureActive(_ session: UUID) async throws {
        try Task.checkCancellation()
        try await StudyGenerationCoordinator.shared.throwUnlessActive(session)
    }
    
    private static func makeSession(
        tools: [any Tool],
        options: FoundationModelAnalysisOptions
    ) -> LanguageModelSession {
        LanguageModelSession(
            model: .default,
            tools: tools,
            instructions: instructions(for: options)
        )
    }
    
    private static func generateArtifact<T: Generable>(
        prompt: String,
        generating type: T.Type,
        session: UUID,
        tools: [any Tool],
        options: FoundationModelAnalysisOptions
    ) async throws -> T {
        try await respondInFreshSession(
            prompt: prompt,
            generating: type,
            session: session,
            tools: tools,
            options: options
        )
    }
    
    private static func generateSummary(
        transcript: String,
        title: String,
        session: UUID,
        tools: [any Tool],
        options: FoundationModelAnalysisOptions,
        regenerationNote: String,
        researchBlock: String,
        onProgress: ProgressHandler? = nil
    ) async throws -> GenerableSummary {
        let chunks = AnalysisText.mapReduceChunks(from: transcript)
        
        guard chunks.count > 1 else {
            let prepared = AnalysisText.prepare(transcript)
            return try await respondInFreshSession(
                prompt: """
                Summarize this lecture in one headline, one paragraph, and bullet takeaways.\(regenerationNote)\(researchBlock)
                
                Transcript:
                \(prepared)
                """,
                generating: GenerableSummary.self,
                session: session,
                tools: tools,
                options: options,
                label: "summary"
            )
        }
        
        // Map-reduce: summarize each chunk in its own session, then merge (TN3193).
        var sectionSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try await ensureActive(session)
            onProgress?("Summarizing segment \(index + 1) of \(chunks.count)…")
            let section = try await respondInFreshSession(
                prompt: """
                Summarize section \(index + 1) of \(chunks.count) from lecture "\(title)".\(regenerationNote)
                
                \(chunk)
                """,
                generating: GenerableChunkSummary.self,
                session: session,
                tools: [],
                options: options,
                label: "summary segment \(index + 1)"
            )
            let bullets = section.bullets.map { "- \($0)" }.joined(separator: "\n")
            sectionSummaries.append("\(section.paragraph)\n\(bullets)")
        }
        
        let merged = sectionSummaries.joined(separator: "\n\n")
        let condensed = AnalysisText.prepare(merged, maxTokens: AnalysisText.perSessionTranscriptTokens)
        
        return try await respondInFreshSession(
            prompt: """
            Merge these section summaries into one cohesive lecture summary.\(regenerationNote)\(researchBlock)
            Title: \(title)
            
            Section summaries:
            \(condensed)
            """,
            generating: GenerableSummary.self,
            session: session,
            tools: tools,
            options: options,
            label: "summary merge"
        )
    }
    
    private static func generateNotes(
        transcript: String,
        title: String,
        summary: GenerableSummary,
        session: UUID,
        scale: AnalysisText.StudyPackScale,
        tools: [any Tool],
        options: FoundationModelAnalysisOptions,
        regenerationNote: String,
        researchBlock: String,
        densityNote: String,
        onProgress: ProgressHandler? = nil
    ) async throws -> GenerableStudyNotes {
        let chunks = AnalysisText.mapReduceChunks(from: transcript)
        
        guard scale.usesMapReduce else {
            let prepared = AnalysisText.prepare(transcript)
            return try await respondInFreshSession(
                prompt: """
                Create thorough structured study notes for this lecture.\(regenerationNote)
                Target \(scale.targetNoteSections) sections with definitions, formulas, examples, and takeaways.
                \(densityNote)
                Add "External context" only when web research is relevant.\(researchBlock)
                
                Transcript:
                \(prepared)
                """,
                generating: GenerableStudyNotes.self,
                session: session,
                tools: tools,
                options: options,
                label: "notes"
            )
        }
        
        var allSections: [GenerableNoteSection] = []
        for (index, chunk) in chunks.enumerated() {
            try await ensureActive(session)
            onProgress?("Notes segment \(index + 1) of \(chunks.count)…")
            let pack = try await respondInFreshSession(
                prompt: """
                Create detailed study notes for section \(index + 1) of \(chunks.count) from "\(title)".\(regenerationNote)
                Cover every major topic in this segment: definitions, formulas, examples, and intuitions.
                Do not summarize briefly — be thorough.\(densityNote)
                
                \(chunk)
                """,
                generating: GenerableNoteSectionPack.self,
                session: session,
                tools: [],
                options: options,
                label: "notes segment \(index + 1)"
            )
            allSections.append(contentsOf: pack.sections)
        }
        
        allSections = Array(allSections.prefix(scale.targetNoteSections))
        return GenerableStudyNotes(
            title: "\(title) — Study Notes",
            sections: allSections
        )
    }
    
    private static func generateFlashcards(
        transcript: String,
        title: String,
        summary: GenerableSummary,
        session: UUID,
        scale: AnalysisText.StudyPackScale,
        options: FoundationModelAnalysisOptions,
        regenerationNote: String,
        researchBlock: String,
        densityNote: String,
        onProgress: ProgressHandler? = nil
    ) async throws -> [FlashCard] {
        let chunks = AnalysisText.mapReduceChunks(from: transcript)
        
        if !scale.usesMapReduce {
            let contextBlock = AnalysisText.studyContext(
                title: title,
                oneLine: summary.oneLine,
                paragraph: summary.paragraph,
                bullets: summary.bullets,
                transcript: transcript,
                researchBlock: researchBlock,
                scale: scale
            )
            let pack = try await respondInFreshSession(
                prompt: """
                Create \(scale.targetFlashcards) flashcards from this lecture.\(regenerationNote)
                Mix concept, definition, and application questions.\(densityNote)
                
                \(contextBlock)
                """,
                generating: GenerableFlashcardPack.self,
                session: session,
                tools: [],
                options: options,
                label: "flashcards"
            )
            return pack.cards.map { FlashCard(front: $0.front, back: $0.back, tag: $0.tag) }
        }
        
        var cards: [FlashCard] = []
        let cardsPerChunk = max(scale.cardsPerChunk.lowerBound, scale.targetFlashcards / max(chunks.count, 1))
        
        for (index, chunk) in chunks.enumerated() {
            try await ensureActive(session)
            onProgress?("Flashcards segment \(index + 1) of \(chunks.count)…")
            let pack = try await respondInFreshSession(
                prompt: """
                Create \(cardsPerChunk) flashcards from section \(index + 1) of \(chunks.count) of "\(title)".\(regenerationNote)
                Focus on key terms, formulas, and ideas from this segment only.\(densityNote)
                
                \(chunk)
                """,
                generating: GenerableFlashcardPack.self,
                session: session,
                tools: [],
                options: options,
                label: "flashcards segment \(index + 1)"
            )
            cards.append(contentsOf: pack.cards.map {
                FlashCard(front: $0.front, back: $0.back, tag: $0.tag)
            })
        }
        
        return dedupeFlashcards(cards, limit: scale.targetFlashcards)
    }
    
    private static func generateConcepts(
        transcript: String,
        title: String,
        summary: GenerableSummary,
        session: UUID,
        scale: AnalysisText.StudyPackScale,
        options: FoundationModelAnalysisOptions,
        regenerationNote: String,
        researchBlock: String,
        densityNote: String,
        onProgress: ProgressHandler? = nil
    ) async throws -> [KeyConcept] {
        let chunks = AnalysisText.mapReduceChunks(from: transcript)
        
        if !scale.usesMapReduce {
            let contextBlock = AnalysisText.studyContext(
                title: title,
                oneLine: summary.oneLine,
                paragraph: summary.paragraph,
                bullets: summary.bullets,
                transcript: transcript,
                researchBlock: researchBlock,
                scale: scale
            )
            let pack = try await respondInFreshSession(
                prompt: """
                List \(scale.targetConcepts) important concepts with clear definitions.\(regenerationNote)
                Include formulas and technical terms where relevant.\(densityNote)
                
                \(contextBlock)
                """,
                generating: GenerableConceptPack.self,
                session: session,
                tools: [],
                options: options,
                label: "concepts"
            )
            return pack.concepts.map {
                KeyConcept(term: $0.term, definition: $0.definition, importance: $0.importance)
            }
        }
        
        var concepts: [KeyConcept] = []
        let conceptsPerChunk = max(
            scale.conceptsPerChunk.lowerBound,
            scale.targetConcepts / max(chunks.count, 1)
        )
        
        for (index, chunk) in chunks.enumerated() {
            try await ensureActive(session)
            onProgress?("Concepts segment \(index + 1) of \(chunks.count)…")
            let pack = try await respondInFreshSession(
                prompt: """
                Extract \(conceptsPerChunk) key concepts from section \(index + 1) of \(chunks.count) of "\(title)".\(regenerationNote)
                Each concept needs a clear term and definition. Mark importance high/medium/low.\(densityNote)
                
                \(chunk)
                """,
                generating: GenerableConceptSegmentPack.self,
                session: session,
                tools: [],
                options: options,
                label: "concepts segment \(index + 1)"
            )
            concepts.append(contentsOf: pack.concepts.map {
                KeyConcept(term: $0.term, definition: $0.definition, importance: $0.importance)
            })
        }
        
        return dedupeConcepts(concepts, limit: scale.targetConcepts)
    }
    
    private static func generateMindMap(
        transcript: String,
        title: String,
        summary: GenerableSummary,
        session: UUID,
        scale: AnalysisText.StudyPackScale,
        options: FoundationModelAnalysisOptions,
        regenerationNote: String,
        researchBlock: String,
        densityNote: String,
        onProgress: ProgressHandler? = nil
    ) async throws -> MindMap {
        let chunks = AnalysisText.mapReduceChunks(from: transcript)
        
        if !scale.usesMapReduce {
            let contextBlock = AnalysisText.studyContext(
                title: title,
                oneLine: summary.oneLine,
                paragraph: summary.paragraph,
                bullets: summary.bullets,
                transcript: transcript,
                researchBlock: researchBlock,
                scale: scale
            )
            let map = try await respondInFreshSession(
                prompt: """
                Build a concept map with up to \(scale.targetMindMapNodes) nodes for this lecture.\(regenerationNote)
                Show how major topics connect.\(densityNote)
                
                \(contextBlock)
                """,
                generating: GenerableMindMap.self,
                session: session,
                tools: [],
                options: options,
                label: "mind map"
            )
            return toMindMap(map)
        }
        
        var segments: [GenerableMindMapSegment] = []
        for (index, chunk) in chunks.enumerated() {
            try await ensureActive(session)
            onProgress?("Concept map segment \(index + 1) of \(chunks.count)…")
            let segment = try await respondInFreshSession(
                prompt: """
                Build a concept map fragment for section \(index + 1) of \(chunks.count) of "\(title)".\(regenerationNote)
                Include a segment topic and 4-7 nodes showing how ideas in this section relate.\(densityNote)
                Use short stable node ids like n1, n2, n3.
                
                \(chunk)
                """,
                generating: GenerableMindMapSegment.self,
                session: session,
                tools: [],
                options: options,
                label: "mind map segment \(index + 1)"
            )
            segments.append(segment)
        }
        
        return mergeMindMapSegments(segments, title: title, nodeLimit: scale.targetMindMapNodes)
    }
    
    private static func toMindMap(_ map: GenerableMindMap) -> MindMap {
        MindMap(
            centralTopic: map.centralTopic,
            nodes: map.nodes.map { MindMapNode(id: $0.id, label: $0.label, level: $0.level) },
            edges: map.edges.map {
                MindMapEdge(id: $0.id, fromId: $0.fromId, toId: $0.toId, relationship: $0.relationship)
            }
        )
    }
    
    private static func mergeMindMapSegments(
        _ segments: [GenerableMindMapSegment],
        title: String,
        nodeLimit: Int
    ) -> MindMap {
        var nodes: [MindMapNode] = [
            MindMapNode(id: "center", label: title, level: 0)
        ]
        var edges: [MindMapEdge] = []
        
        for (index, segment) in segments.enumerated() {
            let branchId = "seg-\(index)"
            nodes.append(MindMapNode(id: branchId, label: segment.segmentTopic, level: 1))
            edges.append(MindMapEdge(
                id: "e-center-\(index)",
                fromId: "center",
                toId: branchId,
                relationship: "includes"
            ))
            
            // Model output can repeat node ids within a segment; uniquingKeysWith
            // avoids the runtime trap of Dictionary(uniqueKeysWithValues:).
            let idMap: [String: String] = Dictionary(
                segment.nodes.map { ($0.id, "\(branchId)-\($0.id)") },
                uniquingKeysWith: { first, _ in first }
            )
            
            for node in segment.nodes {
                let mappedId = idMap[node.id] ?? "\(branchId)-\(node.id)"
                let level = min(2, node.level + 1)
                nodes.append(MindMapNode(id: mappedId, label: node.label, level: level))
            }
            
            for edge in segment.edges {
                guard let fromId = idMap[edge.fromId], let toId = idMap[edge.toId] else { continue }
                edges.append(MindMapEdge(
                    id: "\(branchId)-\(edge.id)",
                    fromId: fromId,
                    toId: toId,
                    relationship: edge.relationship
                ))
            }
            
            if nodes.count >= nodeLimit { break }
        }
        
        if nodes.count > nodeLimit {
            nodes = Array(nodes.prefix(nodeLimit))
        }

        // Drop any dangling edge whose endpoints are not in the final node set
        // (can happen after the node-limit prune or an early loop break).
        let finalIds = Set(nodes.map(\.id))
        edges = edges.filter { finalIds.contains($0.fromId) && finalIds.contains($0.toId) }

        return MindMap(centralTopic: title, nodes: nodes, edges: edges)
    }
    
    private static func dedupeConcepts(_ concepts: [KeyConcept], limit: Int) -> [KeyConcept] {
        var seen = Set<String>()
        var result: [KeyConcept] = []
        
        for concept in concepts {
            let key = concept.term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(concept)
            if result.count >= limit { break }
        }
        
        return result
    }
    
    private static func dedupeFlashcards(_ cards: [FlashCard], limit: Int) -> [FlashCard] {
        var seen = Set<String>()
        var result: [FlashCard] = []
        
        for card in cards {
            let key = card.front.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(card)
            if result.count >= limit { break }
        }
        
        return result
    }
    
    private static func densityInstruction(for scale: AnalysisText.StudyPackScale) -> String {
        switch scale.length {
        case .short:
            return "Lecture length: short. Be clear and complete."
        case .medium:
            return "Lecture length: medium. Include substantive detail in each section."
        case .long:
            return """
            Lecture length: long (\(scale.estimatedTokens) tokens, \(scale.chunkCount) segments).
            This is a dense lecture — do not skip topics. Include formulas, definitions, examples, and intuitions.
            """
        }
    }
    
    private static func respondInFreshSession<T: Generable>(
        prompt: String,
        generating type: T.Type,
        session: UUID,
        tools: [any Tool],
        options: FoundationModelAnalysisOptions,
        label: String = "generation"
    ) async throws -> T {
        try await ensureActive(session)

        // Proactively shrink the prompt to fit the measured context window before
        // spending a round-trip; the catch below still handles the rare overflow.
        let fitted = await fittedPrompt(prompt, options: options, tools: tools)

        do {
            return try await performGeneration(
                prompt: fitted,
                generating: type,
                tools: tools,
                options: options
            )
        } catch {
            try await ensureActive(session)
            
            if isContextWindowError(error) {
                logService.warning("Context window exceeded for \(label); retrying with shorter prompt.")
                let shorter = shortenPrompt(prompt)
                return try await performGeneration(
                    prompt: shorter,
                    generating: type,
                    tools: [],
                    options: options
                )
            }
            
            if isRecoverableGenerationError(error) {
                logService.warning("On-device model returned recoverable error for \(label); retrying once.")
                let shorter = shortenPrompt(prompt)
                return try await performGeneration(
                    prompt: shorter,
                    generating: type,
                    tools: [],
                    options: options
                )
            }
            
            throw error
        }
    }
    
    /// Low temperature for deterministic, faithful extraction (study packs).
    private static let extractionTemperature = 0.3
    /// Headroom reserved for instructions schema + generated output tokens.
    private static let outputTokenReserve = 1_100

    private static func performGeneration<T: Generable>(
        prompt: String,
        generating type: T.Type,
        tools: [any Tool],
        options: FoundationModelAnalysisOptions
    ) async throws -> T {
        let sessionModel = makeSession(tools: tools, options: options)
        let generationOptions = GenerationOptions(temperature: extractionTemperature)
        return try await sessionModel.respond(to: prompt, generating: type, options: generationOptions).content
    }

    /// The model's context window. Uses the documented on-device limit (4096);
    /// once building against the macOS 26.4 SDK this can query
    /// `SystemLanguageModel.default.contextSize` at runtime instead.
    private static func contextSize() -> Int {
        AnalysisText.foundationModelContextWindow
    }

    /// Estimate the prompt against the context window and shrink it (keeping head
    /// + tail) until it fits, reserving headroom for instructions and output.
    /// On the 26.4 SDK, swap the estimates for `model.tokenUsage(for:)`.
    private static func fittedPrompt(
        _ prompt: String,
        options: FoundationModelAnalysisOptions,
        tools: [any Tool]
    ) async -> String {
        let window = contextSize()
        let instructionTokens = AnalysisText.estimatedTokens(for: instructions(for: options))
        let budget = max(256, window - outputTokenReserve - instructionTokens)

        var current = prompt
        for _ in 0..<3 {
            let promptTokens = AnalysisText.estimatedTokens(for: current)
            if promptTokens <= budget { break }
            let shorter = shortenPrompt(current)
            if shorter.count >= current.count { break }
            current = shorter
        }
        return current
    }
    
    private static func shortenPrompt(_ prompt: String) -> String {
        let budget = AnalysisText.perSessionTranscriptTokens * 2
        let maxChars = max(2_000, budget * 3)
        guard prompt.count > maxChars else { return prompt }
        
        let head = prompt.prefix(maxChars * 2 / 3)
        let tail = prompt.suffix(maxChars / 3)
        return """
        \(head)
        
        [... middle omitted to fit on-device context window ...]
        
        \(tail)
        """
    }
    
    private static func isRecoverableGenerationError(_ error: Error) -> Bool {
        // Typed checks first: a guardrail refusal must NOT be retried, and the
        // context-window case is handled by isContextWindowError, not here.
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .guardrailViolation:
                return false
            case .exceededContextWindowSize:
                return false
            default:
                break
            }
        }

        let description = String(describing: error).lowercased()
        // A guardrail/refusal is a deliberate policy decision; do not retry it.
        if description.contains("guardrail") || description.contains("refus") {
            return false
        }
        return description.contains("malformed")
            || description.contains("invalid generation")
            || description.contains("failed to decode")
    }

    private static func isContextWindowError(_ error: Error) -> Bool {
        if let generationError = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generationError {
            return true
        }

        let description = String(describing: error).lowercased()
        return description.contains("context")
            && (description.contains("exceed") || description.contains("window") || description.contains("size"))
    }
    
    private static func instructions(for options: FoundationModelAnalysisOptions) -> String {
        var text = """
        MuseDrop lecture assistant. Ground all study materials in the provided transcript.
        For notes, flashcards, concepts, and mind maps: be thorough — do not over-compress dense lectures.
        For summaries: stay concise.
        Do not invent facts beyond optional web research snippets.
        """
        if options.enableWebResearchTool {
            text += "\nYou may call webResearch for up to 3 focused queries when external context would improve notes."
        }
        if options.forceRegenerate {
            text += "\nRegeneration mode: avoid repeating prior phrasing and produce a meaningfully refreshed study pack."
        }
        return text
    }
}

#endif

struct MediaAnalysisPayload {
    var summary: SummaryResult
    var notes: StudyNotes
    var keyConcepts: [KeyConcept]
    var flashcards: [FlashCard]
    var mindMap: MindMap
    var engine: AIEngineKind
}
