//
//  MediaAnalysisMapper.swift
//  MuseDrop
//

import Foundation

enum MediaAnalysisMapper {
    static func toDownloadItem(_ record: DownloadRecord) -> DownloadItem {
        let mode = ConsumptionMode(rawValue: record.consumptionModeRaw) ?? .download
        let streamKind = record.streamMediaKindRaw.flatMap { StreamMediaKind(rawValue: $0) }
        
        return DownloadItem(
            id: record.id,
            url: record.url,
            title: record.title,
            thumbnail: record.thumbnailPath.map { URL(fileURLWithPath: $0) },
            format: record.format,
            progress: record.progress,
            status: DownloadStatus(rawValue: record.statusRaw) ?? .queued,
            outputPath: record.outputPath.map { URL(fileURLWithPath: $0) },
            createdDate: record.createdAt,
            summaryExists: hasStudyContent(record.studySession),
            errorMessage: record.errorMessage,
            consumptionMode: mode,
            streamURL: record.streamURLString.flatMap { URL(string: $0) },
            streamExpiresAt: record.streamExpiresAt,
            streamMediaKind: streamKind,
            durationSeconds: record.durationSeconds,
            playlistId: record.playlistId,
            playlistTitle: record.playlistTitle
        )
    }
    
    static func apply(_ item: DownloadItem, to record: DownloadRecord) {
        record.url = item.url
        record.title = item.title
        record.thumbnailPath = item.thumbnail?.path
        record.format = item.format
        record.progress = item.progress
        record.statusRaw = item.status.rawValue
        record.outputPath = item.outputPath?.path
        record.createdAt = item.createdDate
        record.errorMessage = item.errorMessage
        record.consumptionModeRaw = item.consumptionMode.rawValue
        record.streamURLString = item.streamURL?.absoluteString
        record.streamExpiresAt = item.streamExpiresAt
        record.streamMediaKindRaw = item.streamMediaKind?.rawValue
        record.durationSeconds = item.durationSeconds
        record.playlistId = item.playlistId
        record.playlistTitle = item.playlistTitle
    }
    
    static func makeDownloadRecord(from item: DownloadItem) -> DownloadRecord {
        DownloadRecord(
            id: item.id,
            url: item.url,
            title: item.title,
            thumbnailPath: item.thumbnail?.path,
            format: item.format,
            progress: item.progress,
            statusRaw: item.status.rawValue,
            outputPath: item.outputPath?.path,
            createdAt: item.createdDate,
            errorMessage: item.errorMessage,
            consumptionModeRaw: item.consumptionMode.rawValue,
            streamURLString: item.streamURL?.absoluteString,
            streamExpiresAt: item.streamExpiresAt,
            streamMediaKindRaw: item.streamMediaKind?.rawValue,
            durationSeconds: item.durationSeconds,
            playlistId: item.playlistId,
            playlistTitle: item.playlistTitle
        )
    }
    
    static func toMediaAnalysis(_ session: StudySessionRecord, downloadId: UUID) -> MediaAnalysis? {
        guard let transcript = session.transcript, !transcript.text.isEmpty else {
            return nil
        }
        
        let engine = AIEngineKind(rawValue: session.engineRaw) ?? .naturalLanguageFallback
        
        return MediaAnalysis(
            id: session.id,
            downloadId: downloadId,
            mediaTitle: session.mediaTitle,
            transcript: MediaTranscript(
                text: transcript.text,
                createdAt: transcript.createdAt,
                engine: TranscriptionEngine(rawValue: transcript.engineRaw) ?? .speechRecognizer,
                coveredSeconds: transcript.coveredSeconds,
                sourceDurationSeconds: transcript.sourceDurationSeconds,
                coverageNote: transcript.coverageNote
            ),
            summary: SummaryResult(
                oneLine: session.summaryOneLine,
                paragraph: session.summaryParagraph,
                bullets: session.summaryBullets.sorted { $0.order < $1.order }.map(\.text),
                timestamp: session.updatedAt
            ),
            notes: StudyNotes(
                title: session.notesTitle,
                sections: session.noteSections.sorted { $0.order < $1.order }.map { section in
                    NoteSection(
                        id: "section-\(section.order)",
                        heading: section.heading,
                        content: section.content,
                        bullets: section.bullets.sorted { $0.order < $1.order }.map(\.text)
                    )
                }
            ),
            keyConcepts: session.keyConcepts.sorted { $0.order < $1.order }.map {
                KeyConcept(id: "concept-\($0.order)", term: $0.term, definition: $0.definition, importance: $0.importance)
            },
            flashcards: session.flashcards.sorted { $0.order < $1.order }.map {
                FlashCard(id: "card-\($0.order)", front: $0.front, back: $0.back, tag: $0.tag)
            },
            mindMap: MindMap(
                centralTopic: session.mindMapCentralTopic,
                nodes: session.mindMapNodes.map {
                    MindMapNode(id: $0.nodeId, label: $0.label, level: $0.level)
                },
                edges: session.mindMapEdges.map {
                    MindMapEdge(id: $0.edgeId, fromId: $0.fromId, toId: $0.toId, relationship: $0.relationship)
                }
            ),
            engine: engine,
            createdAt: session.createdAt
        )
    }
    
    static func apply(_ analysis: MediaAnalysis, to session: StudySessionRecord) {
        session.mediaTitle = analysis.mediaTitle
        session.engineRaw = analysis.engine.rawValue
        session.updatedAt = Date()
        session.summaryOneLine = analysis.summary.oneLine
        session.summaryParagraph = analysis.summary.paragraph
        session.notesTitle = analysis.notes.title
        session.mindMapCentralTopic = analysis.mindMap.centralTopic
        
        replaceSummaryBullets(analysis.summary.bullets, in: session)
        replaceNoteSections(analysis.notes, in: session)
        replaceFlashcards(analysis.flashcards, in: session)
        replaceKeyConcepts(analysis.keyConcepts, in: session)
        replaceMindMap(analysis.mindMap, in: session)
        
        if let existing = session.transcript {
            existing.text = analysis.transcript.text
            existing.createdAt = analysis.transcript.createdAt
            existing.engineRaw = analysis.transcript.engine.rawValue
            existing.coveredSeconds = analysis.transcript.coveredSeconds
            existing.sourceDurationSeconds = analysis.transcript.sourceDurationSeconds
            existing.coverageNote = analysis.transcript.coverageNote
        } else {
            let transcript = TranscriptRecord(
                text: analysis.transcript.text,
                createdAt: analysis.transcript.createdAt,
                engineRaw: analysis.transcript.engine.rawValue,
                coveredSeconds: analysis.transcript.coveredSeconds,
                sourceDurationSeconds: analysis.transcript.sourceDurationSeconds,
                coverageNote: analysis.transcript.coverageNote
            )
            transcript.studySession = session
            session.transcript = transcript
        }
    }
    
    static func hasStudyContent(_ session: StudySessionRecord?) -> Bool {
        guard let session else { return false }
        return !session.summaryOneLine.isEmpty
            || !session.noteSections.isEmpty
            || !session.flashcards.isEmpty
            || !session.keyConcepts.isEmpty
            || !session.mindMapNodes.isEmpty
    }
    
    static func artifactKinds(in session: StudySessionRecord) -> Set<AIStudyArtifactKind> {
        var kinds = Set<AIStudyArtifactKind>()
        if session.transcript != nil { kinds.insert(.transcript) }
        if !session.summaryOneLine.isEmpty { kinds.insert(.summary) }
        if !session.noteSections.isEmpty { kinds.insert(.notes) }
        if !session.flashcards.isEmpty { kinds.insert(.flashcards) }
        if !session.mindMapNodes.isEmpty { kinds.insert(.mindMap) }
        if !session.keyConcepts.isEmpty { kinds.insert(.concepts) }
        return kinds
    }
    
    // MARK: - Private helpers
    
    private static func replaceSummaryBullets(_ bullets: [String], in session: StudySessionRecord) {
        session.summaryBullets.removeAll()
        for (index, text) in bullets.enumerated() {
            let bullet = OrderedTextRecord(order: index, text: text)
            bullet.summarySession = session
            session.summaryBullets.append(bullet)
        }
    }
    
    private static func replaceNoteSections(_ notes: StudyNotes, in session: StudySessionRecord) {
        session.noteSections.removeAll()
        for (index, section) in notes.sections.enumerated() {
            let bullets = section.bullets.enumerated().map { bulletIndex, text in
                OrderedTextRecord(order: bulletIndex, text: text)
            }
            let record = NoteSectionRecord(
                order: index,
                heading: section.heading,
                content: section.content,
                bullets: bullets
            )
            record.studySession = session
            for bullet in bullets {
                bullet.noteSection = record
            }
            session.noteSections.append(record)
        }
    }
    
    private static func replaceFlashcards(_ cards: [FlashCard], in session: StudySessionRecord) {
        session.flashcards.removeAll()
        for (index, card) in cards.enumerated() {
            let record = FlashcardRecord(order: index, front: card.front, back: card.back, tag: card.tag)
            record.studySession = session
            session.flashcards.append(record)
        }
    }
    
    private static func replaceKeyConcepts(_ concepts: [KeyConcept], in session: StudySessionRecord) {
        session.keyConcepts.removeAll()
        for (index, concept) in concepts.enumerated() {
            let record = KeyConceptRecord(
                order: index,
                term: concept.term,
                definition: concept.definition,
                importance: concept.importance
            )
            record.studySession = session
            session.keyConcepts.append(record)
        }
    }
    
    private static func replaceMindMap(_ mindMap: MindMap, in session: StudySessionRecord) {
        session.mindMapNodes.removeAll()
        session.mindMapEdges.removeAll()
        
        for node in mindMap.nodes {
            let record = MindMapNodeRecord(nodeId: node.id, label: node.label, level: node.level)
            record.studySession = session
            session.mindMapNodes.append(record)
        }
        
        for edge in mindMap.edges {
            let record = MindMapEdgeRecord(
                edgeId: edge.id,
                fromId: edge.fromId,
                toId: edge.toId,
                relationship: edge.relationship
            )
            record.studySession = session
            session.mindMapEdges.append(record)
        }
    }
}
