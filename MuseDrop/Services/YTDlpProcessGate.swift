//
//  YTDlpProcessGate.swift
//  MuseDrop
//
//  Serializes yt-dlp invocations so stream playback and study transcription
//  don't compete for the same YouTube session (rate limits / flaky URLs).
//

import Foundation

actor YTDlpProcessGate {
    static let shared = YTDlpProcessGate()
    
    private var locked = false
    private var waitQueue: [CheckedContinuation<Void, Never>] = []
    
    private init() {}
    
    func run<T>(_ operation: () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
    
    private func acquire() async {
        if !locked {
            locked = true
            return
        }
        
        await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }
    
    private func release() {
        if waitQueue.isEmpty {
            locked = false
        } else {
            let next = waitQueue.removeFirst()
            next.resume()
        }
    }
}
