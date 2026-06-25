//
//  StudyGenerationCoordinator.swift
//  MuseDrop
//
//  Session-scoped pause / cancel for study pack and transcript generation.
//

import Foundation

actor StudyGenerationCoordinator {
    static let shared = StudyGenerationCoordinator()
    
    private var activeSession: UUID?
    private var cancelledSessions = Set<UUID>()
    private var paused = false
    
    private init() {}
    
    /// Starts a new generation session. Supersedes any in-flight work tied to older sessions.
    func begin(session: UUID) {
        activeSession = session
        cancelledSessions.remove(session)
        paused = false
    }
    
    func pause() {
        paused = true
    }
    
    func resume() {
        paused = false
    }
    
    func cancel(session: UUID) {
        cancelledSessions.insert(session)
        paused = false
    }
    
    func cancelActive() {
        if let session = activeSession {
            cancelledSessions.insert(session)
        }
        paused = false
    }
    
    func throwUnlessActive(_ session: UUID) throws {
        if Task.isCancelled {
            throw CancellationError()
        }
        if activeSession != session {
            throw CancellationError()
        }
        if cancelledSessions.contains(session) {
            throw CancellationError()
        }
    }
    
    func waitIfPaused(_ session: UUID) async throws {
        while paused {
            try throwUnlessActive(session)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try throwUnlessActive(session)
    }
    
    func throwUnlessActiveAndWait(_ session: UUID) async throws {
        try throwUnlessActive(session)
        try await waitIfPaused(session)
    }
}
