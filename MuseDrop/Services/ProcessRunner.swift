//
//  ProcessRunner.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation

// Thread-safe data container for process output
private class ProcessData {
    private let queue = DispatchQueue(label: "com.musedrop.processdata")
    private var _stdout = Data()
    private var _stderr = Data()
    
    func appendStdout(_ data: Data) {
        queue.sync { _stdout.append(data) }
    }
    
    func appendStderr(_ data: Data) {
        queue.sync { _stderr.append(data) }
    }
    
    func getOutputs() -> (stdout: String, stderr: String) {
        return queue.sync {
            (String(data: _stdout, encoding: .utf8) ?? "",
             String(data: _stderr, encoding: .utf8) ?? "")
        }
    }
    
    func getStderr() -> String {
        return queue.sync {
            String(data: _stderr, encoding: .utf8) ?? ""
        }
    }
}

/// One instance per concurrent operation (download, transcript job, etc.).
/// Do not share a single instance across overlapping work.
final class ProcessRunner: @unchecked Sendable {
    private let stateLock = NSLock()
    private var currentTask: Process?
    private var cancelRequested = false
    private let logService = LogService.shared
    
    private func storeTask(_ process: Process) {
        stateLock.lock()
        currentTask = process
        stateLock.unlock()
    }
    
    private func clearTask() {
        stateLock.lock()
        currentTask = nil
        stateLock.unlock()
    }
    
    private func consumeCancelRequest() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        let cancelled = cancelRequested
        cancelRequested = false
        return cancelled
    }

    /// Clears any stale cancel flag left over from a previous run. Called at the
    /// start of every invocation so a timeout/cancel that fired after the prior
    /// process had already exited cannot poison the next run on this instance.
    private func resetCancel() {
        stateLock.lock()
        cancelRequested = false
        stateLock.unlock()
    }
    
    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        environment: [String: String]? = nil
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withThrowingTaskGroup(of: (String, String, Int32).self) { group in
            group.addTask {
                try await self.runProcess(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    environment: environment
                )
            }
            
            if let timeout, timeout > 0 {
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self.cancel()
                    throw ProcessError.timedOut(seconds: timeout)
                }
            }
            
            guard let result = try await group.next() else {
                throw ProcessError.executionFailed(NSError(domain: "ProcessRunner", code: -1))
            }
            group.cancelAll()
            return result
        }
    }
    
    private func runProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        resetCancel()
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            process.environment = Self.processEnvironment(extra: environment)
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            let processData = ProcessData()
            
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    processData.appendStdout(data)
                }
            }
            
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    processData.appendStderr(data)
                }
            }
            
            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self.clearTask()

                // Drain any data still buffered in the pipes after the handlers
                // were removed, otherwise the final chunk (e.g. yt-dlp's last -j
                // JSON line) can be lost.
                if let restOut = try? stdoutPipe.fileHandleForReading.readToEnd(), !restOut.isEmpty {
                    processData.appendStdout(restOut)
                }
                if let restErr = try? stderrPipe.fileHandleForReading.readToEnd(), !restErr.isEmpty {
                    processData.appendStderr(restErr)
                }

                let (stdout, stderr) = processData.getOutputs()
                
                if self.consumeCancelRequest() {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: (stdout, stderr, process.terminationStatus))
                } else {
                    continuation.resume(throwing: ProcessError.nonZeroExit(code: process.terminationStatus, stderr: stderr))
                }
            }
            
            do {
                guard FileManager.default.fileExists(atPath: executable.path) else {
                    continuation.resume(throwing: ProcessError.executableNotFound)
                    return
                }
                
                if !FileManager.default.isExecutableFile(atPath: executable.path) {
                    logService.warning("File at \(executable.path) reports as not executable, but attempting to run anyway (sandbox may allow execution)")
                    FileUtils.ensureBinaryReady(executable)
                }
                
                try process.run()
                self.storeTask(process)
            } catch {
                self.clearTask()
                logService.error("Failed to run process: \(error.localizedDescription)")
                continuation.resume(throwing: ProcessError.executionFailed(error))
            }
        }
    }
    
    func runWithProgress(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        resetCancel()
        return AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            process.environment = Self.processEnvironment(extra: environment)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let processData = ProcessData()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                    continuation.yield(line)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    processData.appendStderr(data)
                    if let line = String(data: data, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }
            }

            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self.clearTask()

                // Drain any data still buffered in the pipes after the handlers
                // were removed so the final line isn't truncated.
                if let restOut = try? stdoutPipe.fileHandleForReading.readToEnd(), !restOut.isEmpty {
                    if let line = String(data: restOut, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }
                if let restErr = try? stderrPipe.fileHandleForReading.readToEnd(), !restErr.isEmpty {
                    processData.appendStderr(restErr)
                    if let line = String(data: restErr, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }

                if self.consumeCancelRequest() {
                    continuation.finish(throwing: CancellationError())
                    return
                }

                let stderrString = processData.getStderr()

                if process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: ProcessError.nonZeroExit(code: process.terminationStatus, stderr: stderrString))
                }
            }

            // Terminate the child and tear down handlers if the consumer cancels
            // or the stream otherwise finishes. Capturing `process` here also
            // keeps it alive for the lifetime of the stream (we no longer block
            // a cooperative thread on waitUntilExit to retain it).
            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }

            do {
                guard FileManager.default.fileExists(atPath: executable.path) else {
                    continuation.finish(throwing: ProcessError.executableNotFound)
                    return
                }

                if !FileManager.default.isExecutableFile(atPath: executable.path) {
                    logService.warning("File at \(executable.path) reports as not executable, but attempting to run anyway (sandbox may allow execution)")
                    FileUtils.ensureBinaryReady(executable)
                }

                self.storeTask(process)
                try process.run()
            } catch {
                self.clearTask()
                logService.error("Failed to run process: \(error.localizedDescription)")
                continuation.finish(throwing: ProcessError.executionFailed(error))
            }
        }
    }
    
    func cancel() {
        stateLock.lock()
        cancelRequested = true
        let task = currentTask
        currentTask = nil
        stateLock.unlock()
        task?.terminate()
    }
    
    private static func processEnvironment(extra: [String: String]? = nil) -> [String: String] {
        let binDir = PathUtils.binDirectory
        var environment = ProcessInfo.processInfo.environment
        let commonPaths = PathUtils.latexBinDirectories() + [
            binDir.path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        if let currentPath = environment["PATH"] {
            environment["PATH"] = commonPaths.joined(separator: ":") + ":" + currentPath
        } else {
            environment["PATH"] = commonPaths.joined(separator: ":")
        }

        // Caller-supplied overrides (e.g. IPFS_PATH for the kubo daemon).
        if let extra {
            for (key, value) in extra { environment[key] = value }
        }
        return environment
    }
}

enum ProcessError: LocalizedError {
    case nonZeroExit(code: Int32, stderr: String)
    case executableNotFound
    case executionFailed(Error)
    case timedOut(seconds: TimeInterval)
    
    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let stderr):
            return "Process exited with code \(code): \(stderr)"
        case .executableNotFound:
            return "Executable not found"
        case .executionFailed(let error):
            return "Execution failed: \(error.localizedDescription)"
        case .timedOut(let seconds):
            return "Process timed out after \(Int(seconds)) seconds"
        }
    }
}
