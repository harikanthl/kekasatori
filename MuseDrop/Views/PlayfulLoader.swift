//
//  PlayfulLoader.swift
//  MuseDrop
//
//  A playful looping Lottie loader for waits across the app. Instead of a bare spinner,
//  a random critter (dancing cat, scootering crocodile, balloon corgi…) loops while we
//  wait, cycling to a new one during long waits. Animations are raw Lottie `.json`
//  bundled under Resources and loaded by name.
//
//  Uses the native SwiftUI `LottieView` with `.resizable().aspectRatio(.fit)`: the older
//  AppKit `contentMode` approach is overridden by SwiftUI's intrinsic size, which made
//  some artboards (e.g. the owl) render at native size and blow past the frame. Resizable
//  fit scales the whole animation into `size` — no overflow, no crop.
//

import SwiftUI
import Lottie

struct PlayfulLoader: View {
    /// Square edge length for the animation.
    var size: CGFloat = 180
    /// Pin a specific animation; when nil a random one is chosen (and cycled).
    var animation: String? = nil
    /// Seconds before swapping to a different random critter during a long wait.
    var cycleInterval: TimeInterval = 12

    /// Starts random, then cycles to a different critter every `cycleInterval` so a single
    /// long wait never shows the same animation the whole time. Across waits it's varied too.
    @State private var chosen = PlayfulLoader.animations.randomElement() ?? "cat"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bundled animation names (filenames without extension under Resources).
    static let animations = [
        "dance-cat", "salad-cat", "corgi-balloon", "crocodile-scooter", "toucan",
        "sophie-hatter", "friendly-owl", "palm-dude", "rolling-animals", "cat",
    ]

    var body: some View {
        LottieView(animation: .named(animation ?? chosen))
            .looping()
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task {
                // Cycle only when not pinned and motion is allowed.
                guard animation == nil, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(cycleInterval))
                    if Task.isCancelled { break }
                    var next = chosen
                    while next == chosen { next = Self.animations.randomElement() ?? chosen }
                    withAnimation(.easeInOut(duration: 0.4)) { chosen = next }
                }
            }
    }
}
