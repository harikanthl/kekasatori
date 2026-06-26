//
//  CommunityIdentity.swift
//  MuseDrop
//
//  The local user's community identity, backed by a real Nostr keypair
//  (nostr-sdk-ios). The secret key lives in the Keychain; the derived public key
//  + display handle in UserDefaults. The same `keypair` signs published events in
//  `NostrCommunityService`, so the author's `publicKey` always matches the signer.
//

import Foundation
import NostrSDK

final class CommunityIdentity {
    static let shared = CommunityIdentity()

    private(set) var author: CommunityAuthor

    /// The Nostr keypair derived from the Keychain secret. Used to sign events.
    let keypair: Keypair

    private let handleKey = "community.identity.handle"
    private let publicKeyKey = "community.identity.publicKey"

    private init() {
        let defaults = UserDefaults.standard

        // Load (or mint) the secret key, then derive the keypair from it. The
        // legacy stub stored a random 32-byte hex secret, which is also a valid
        // Nostr secret key, so existing identities carry over unchanged.
        let resolved = Self.loadOrCreateKeypair()
        self.keypair = resolved

        // The public key is fully determined by the secret. Persist the hex form,
        // overwriting any legacy placeholder that didn't match the secret.
        let publicKey = resolved.publicKey.hex
        if defaults.string(forKey: publicKeyKey) != publicKey {
            defaults.set(publicKey, forKey: publicKeyKey)
        }

        let handle: String
        if let existing = defaults.string(forKey: handleKey) {
            handle = existing
        } else {
            handle = "anon-\(resolved.publicKey.npub.suffix(6))"
            defaults.set(handle, forKey: handleKey)
        }

        author = CommunityAuthor(handle: handle, publicKey: publicKey)
    }

    /// Update the display handle (does not change the keypair).
    func setHandle(_ newHandle: String) {
        let trimmed = newHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: handleKey)
        author = CommunityAuthor(handle: trimmed, publicKey: author.publicKey)
    }

    private static func loadOrCreateKeypair() -> Keypair {
        let account = KeychainService.Account.communitySecretKey

        if let stored = KeychainService.get(account), let keypair = Keypair(hex: stored) {
            return keypair
        }

        // No secret yet (or a corrupt one) — generate a fresh keypair and persist
        // its secret in hex so it round-trips through `Keypair(hex:)` next launch.
        // Generation only fails on catastrophic crypto-init failure; retry a few
        // times before giving up.
        for _ in 0..<5 {
            if let keypair = Keypair() {
                KeychainService.set(keypair.privateKey.hex, for: account)
                return keypair
            }
        }
        fatalError("Unable to generate a Nostr keypair for the community identity.")
    }
}
