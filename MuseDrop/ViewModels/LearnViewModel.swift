//
//  LearnViewModel.swift
//  MuseDrop
//
//  Drives the Learn tab: pick a challenge, edit code, Run (just your code) or
//  Check (your code + the hidden test) in a container. A passing Check exits 0
//  and marks the challenge complete. Code + completion persist.
//

import Foundation

@MainActor
final class LearnViewModel: ObservableObject {
    enum CheckResult { case passed, failed }

    @Published private(set) var selected: Challenge?
    @Published var code: String = ""
    @Published private(set) var output: String = ""
    @Published private(set) var isRunning = false
    @Published private(set) var runtime: ContainerRuntimeStatus?
    @Published private(set) var result: CheckResult?
    @Published private(set) var completed: Set<String>

    let challenges = ChallengeStore.all

    private var runner: ProcessRunner?
    private var codeByChallenge: [String: String]

    init() {
        codeByChallenge = Self.loadCode()
        completed = Self.loadCompleted()
        checkRuntime()
        select(ChallengeStore.all.first)
    }

    var canRun: Bool { !isRunning && (runtime?.isReady ?? false) && selected != nil }
    func isCompleted(_ challenge: Challenge) -> Bool { completed.contains(challenge.id) }

    /// Loss values scraped from output lines containing "loss" — drives the
    /// Charts visualiser. Takes the last number on each such line.
    var lossSeries: [Double] {
        var values: [Double] = []
        let numeric = CharacterSet(charactersIn: "0123456789.-+eE")
        for line in output.split(separator: "\n") where line.lowercased().contains("loss") {
            let token = line.unicodeScalars.split { !numeric.contains($0) }
                .map(String.init).compactMap(Double.init).last
            if let token { values.append(token) }
        }
        return values
    }

    func select(_ challenge: Challenge?) {
        if let current = selected { codeByChallenge[current.id] = code }
        Self.saveCode(codeByChallenge)
        selected = challenge
        output = ""
        result = nil
        code = challenge.map { codeByChallenge[$0.id] ?? $0.starter } ?? ""
    }

    func resetToStarter() {
        guard let challenge = selected else { return }
        code = challenge.starter
        result = nil
    }

    func checkRuntime() {
        Task { @MainActor [weak self] in self?.runtime = await ContainerRuntime.check() }
    }

    func run(check: Bool) {
        guard let challenge = selected,
              let status = runtime, status.isReady, let cli = status.executable, !isRunning else { return }

        codeByChallenge[challenge.id] = code
        Self.saveCode(codeByChallenge)
        output = ""
        result = nil
        isRunning = true

        let script = check ? challenge.checkScript(userCode: code) : challenge.runScript(userCode: code)
        var env: [String: String] = [:]
        if challenge.needsKaggle,
           let user = KeychainService.get(KeychainService.Account.kaggleUsername),
           let key = KeychainService.get(KeychainService.Account.kaggleKey),
           !user.isEmpty, !key.isEmpty {
            env["KAGGLE_USERNAME"] = user
            env["KAGGLE_KEY"] = key
        }
        let spec = CodeRunSpec(language: challenge.language, image: challenge.image, code: script,
                               dataFiles: challenge.dataFiles, env: env)
        let runner = ProcessRunner()
        self.runner = runner

        Task { @MainActor [weak self] in
            do {
                let dir = try CodeRunService.stage(spec)
                defer { try? FileManager.default.removeItem(at: dir) }
                let args = CodeRunService.buildArguments(
                    image: spec.resolvedImage, hostWorkdir: dir.path,
                    runCommand: spec.language.runCommand(file: spec.language.fileName),
                    env: spec.env)
                for try await line in runner.runWithProgress(executable: cli, arguments: args) {
                    self?.output += line
                }
                self?.finish(check: check, passed: true)
            } catch is CancellationError {
                self?.finishStopped()
            } catch {
                if case ProcessError.nonZeroExit = error {
                    self?.finish(check: check, passed: false)
                } else {
                    self?.output += "\n" + error.localizedDescription
                    self?.finishStopped()
                }
            }
        }
    }

    func stop() {
        runner?.cancel()
        runner = nil
        isRunning = false
    }

    private func finish(check: Bool, passed: Bool) {
        isRunning = false
        runner = nil
        guard check else { return }
        result = passed ? .passed : .failed
        if passed, let challenge = selected {
            completed.insert(challenge.id)
            Self.saveCompleted(completed)
        }
    }

    private func finishStopped() {
        isRunning = false
        runner = nil
    }

    // MARK: - Persistence

    private static let codeKey = "learn.code"
    private static let completedKey = "learn.completed"

    private static func loadCode() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: codeKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }
    private static func saveCode(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) { UserDefaults.standard.set(data, forKey: codeKey) }
    }
    private static func loadCompleted() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: completedKey) ?? [])
    }
    private static func saveCompleted(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: completedKey)
    }
}
