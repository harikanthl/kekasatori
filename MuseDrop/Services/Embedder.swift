//
//  Embedder.swift
//  MuseDrop
//
//  Text → vector for memory recall (docs/agentic-memory.md). The store is
//  embedder-agnostic: M0 ships a dependency-free, deterministic `HashingEmbedder`
//  (good enough to exercise + unit-test cosine recall); a real on-device embedder
//  (NaturalLanguage / a small local model) drops in later behind the same protocol,
//  with BYOK as an opt-in upgrade.
//

import Foundation

protocol Embedder: Sendable {
    var dimensions: Int { get }
    func embed(_ text: String) -> [Float]
}

/// Hashed bag-of-tokens into a fixed-width, L2-normalised vector. Deterministic
/// across launches (FNV-1a, not Swift's per-run-seeded Hasher), so embeddings can
/// be persisted and tests are stable.
struct HashingEmbedder: Embedder {
    let dimensions: Int

    init(dimensions: Int = 128) { self.dimensions = dimensions }

    func embed(_ text: String) -> [Float] {
        var v = [Float](repeating: 0, count: dimensions)
        for token in Self.tokenize(text) {
            let h = Self.fnv1a(token)
            let idx = Int(h % UInt64(dimensions))
            let sign: Float = ((h >> 33) & 1) == 0 ? 1 : -1   // signed hashing trick
            v[idx] += sign
        }
        let norm = sqrt(v.reduce(Float(0)) { $0 + $1 * $1 })
        if norm > 0 { for i in v.indices { v[i] /= norm } }
        return v
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Cosine similarity for L2-normalised vectors (i.e. the dot product). Returns 0
/// for mismatched/empty vectors.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    for i in a.indices { dot += a[i] * b[i] }
    return dot
}
