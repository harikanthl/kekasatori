//
//  RunPodServerless.swift
//  MuseDrop
//
//  Phase 3b #2 — RunPod Serverless (the InferenceTarget tier). A RunPod
//  serverless deployment exposes an OpenAI-compatible API at
//  `https://api.runpod.ai/v2/{endpointId}/openai/v1`, authed with the account's
//  RunPod API key. Unlike the HF router there is no shared catalog URL: each
//  endpoint is created by the user and addressed by its own id. So this is pure
//  URL/profile construction — it drops a served model straight into the Compare
//  arena and the Run eval harness via `ModelProfile` + `directEndpoint`.
//
//  No network here — building the endpoint URL and the profile is all pure, so
//  it is unit-tested in isolation (RunPodServerlessTests). The provisioning
//  tier (JobTarget / lifecycle / cost meter) is Slice B.
//

import Foundation

enum RunPodServerless {
    /// Where to create endpoints / API keys (shown in the add sheet).
    static let consoleURL = "https://www.runpod.io/console/serverless"

    /// Build the OpenAI-compatible base URL for a RunPod serverless endpoint.
    ///
    /// Accepts either a bare endpoint id (`"abc123xyz"`) or anything the user
    /// pasted that contains one — the full base URL, a `…/openai/v1/...` path, or
    /// the console deep-link — and normalizes to
    /// `https://api.runpod.ai/v2/{id}/openai/v1`. Returns nil when no plausible
    /// id can be extracted.
    static func baseURL(forEndpoint raw: String) -> String? {
        guard let id = endpointID(from: raw) else { return nil }
        return "https://api.runpod.ai/v2/\(id)/openai/v1"
    }

    /// Base for the serverless **jobs** API (`/run`, `/status/{id}`, `/cancel/{id}`)
    /// — the ephemeral GPU-job tier used by the compute dial's `RunPodBackend`,
    /// distinct from the `/openai/v1` inference base above.
    static func jobsBaseURL(endpointID id: String) -> String? {
        guard isValidID(id) else { return nil }
        return "https://api.runpod.ai/v2/\(id)"
    }

    /// Extract the endpoint id from user input. RunPod ids are short
    /// alphanumerics; we pull the `v2/{id}` segment when a URL is pasted,
    /// otherwise treat the trimmed token itself as the id.
    static func endpointID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Pasted a URL/path containing `v2/{id}` → take the segment after `v2`.
        if let range = trimmed.range(of: "v2/", options: [.caseInsensitive]) {
            let tail = trimmed[range.upperBound...]
            let id = tail.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
            return isValidID(id) ? id : nil
        }

        // Otherwise the whole token should be the bare id.
        return isValidID(trimmed) ? trimmed : nil
    }

    /// RunPod endpoint ids are URL-path-safe alphanumerics (plus `-`/`_`); reject
    /// anything with spaces, slashes, or scheme punctuation so we never build a
    /// malformed endpoint URL.
    static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Build a Compare/Run `ModelProfile` for a served RunPod endpoint. The key is
    /// pulled from the Keychain at request time via the `.runPod` preset, so it is
    /// never stored on the profile. Returns nil for an unusable endpoint/model.
    static func makeProfile(label: String, endpoint: String, modelId: String) -> ModelProfile? {
        guard let base = baseURL(forEndpoint: endpoint) else { return nil }
        let model = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedLabel.isEmpty ? model : trimmedLabel
        return ModelProfile(label: name, preset: .runPod, modelId: model, baseURL: base)
    }
}
