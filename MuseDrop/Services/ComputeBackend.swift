//
//  ComputeBackend.swift
//  MuseDrop
//
//  The one seam that makes the compute dial possible: a backend launches a
//  `RunRequest` and yields a uniform `RunEvent` stream, regardless of whether the
//  work runs in a local container or on a remote GPU (docs/cockpit-architecture.md
//  §3.5). Phase A ships `LocalContainerBackend`; Phase B adds `RunPodBackend`
//  conforming to the same protocol, so nothing upstream changes when you promote.
//

import Foundation

/// Provider-agnostic description of a containerised job — image + command + env +
/// files (name → base64 contents). Both `RunPodBackend` and `ModalBackend` consume
/// this, so adding a GPU provider is one new backend, not a new payload format.
struct ContainerJobSpec: Codable, Equatable, Sendable {
    var image: String?
    var command: [String]
    var env: [String: String]
    var files: [String: String]

    /// Map a portable request to a job spec. `.command` (raw docker args) isn't
    /// portable to a remote provider → nil (remote runs use the `.code` payload).
    static func from(_ request: RunRequest) -> ContainerJobSpec? {
        switch request.payload {
        case .code(let spec):
            return ContainerJobSpec(
                image: spec.resolvedImage,
                command: spec.language.runCommand(file: spec.language.fileName),
                env: spec.env,
                files: [spec.language.fileName: Data(spec.code.utf8).base64EncodedString()]
            )
        case .command:
            return nil
        }
    }
}

protocol ComputeBackend: AnyObject {
    var capabilities: ComputeTarget.Capabilities { get }

    /// Launch the request and stream events. The stream is non-throwing in spirit:
    /// failures arrive as `.status(.failed(_))` then the stream finishes, so every
    /// outcome (success / failure / cancel) is a terminal `.status` event.
    func launch(_ request: RunRequest) -> AsyncThrowingStream<RunEvent, Error>

    /// Cancel the in-flight run (and, for remote targets, deprovision).
    func cancel() async
}

enum ComputeBackendFactory {
    /// Build the backend for a target. Local needs the detected runtime status to
    /// resolve the engine CLI; remote backends arrive in later phases.
    static func make(for target: ComputeTarget, runtime: ContainerRuntimeStatus?) -> ComputeBackend? {
        switch target.location {
        case .local:
            guard let runtime else { return nil }
            return LocalContainerBackend(target: target, runtime: runtime)
        case .runpodServerless, .runpodPod, .modal:
            return nil  // remote backends are built with credentials (see ComputeTargetStore)
        }
    }
}
