//
//  ManimEnvironment.swift
//  MuseDrop
//

import Foundation

struct ManimEnvironmentStatus: Sendable {
    let manimPath: URL?
    let latexPath: URL?
    let isReady: Bool
    
    var statusMessage: String {
        if isReady {
            return "Manim and LaTeX are ready"
        }
        if manimPath == nil, latexPath == nil {
            return "Install Manim and LaTeX to enable math animations"
        }
        if manimPath == nil {
            return "Manim not found — install with Homebrew"
        }
        return "LaTeX not found — install BasicTeX or MacTeX"
    }
    
    var installHint: String {
        """
        brew install manim
        brew install --cask basictex
        sudo tlmgr update --self
        sudo tlmgr install amsfonts standalone preview dvisvgm
        """
    }
}

enum ManimEnvironment {
    private static let customPathKey = "manimExecutablePath"
    
    static func customExecutablePath() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: customPathKey),
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
    
    static func setCustomExecutablePath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: customPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: customPathKey)
        }
    }
    
    static func check() async -> ManimEnvironmentStatus {
        let manim = await resolveManimPath()
        let latex = resolveLatexPath()
        return ManimEnvironmentStatus(
            manimPath: manim,
            latexPath: latex,
            isReady: manim != nil && latex != nil
        )
    }
    
    static func resolveManimPath() async -> URL? {
        if let custom = customExecutablePath() {
            return custom
        }
        
        let candidates = [
            "/opt/homebrew/bin/manim",
            "/usr/local/bin/manim",
            "/opt/homebrew/Caskroom/miniforge/base/bin/manim"
        ]
        
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        
        return await which("manim")
    }
    
    private static func resolveLatexPath() -> URL? {
        PathUtils.resolveLatexExecutable()
    }
    
    private static func which(_ command: String) async -> URL? {
        let runner = ProcessRunner()
        do {
            let result = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/which"),
                arguments: [command],
                timeout: 5
            )
            guard result.exitCode == 0 else { return nil }
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }
}
