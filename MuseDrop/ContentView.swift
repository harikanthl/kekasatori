//
//  ContentView.swift
//  MuseDrop
//
//  Created by harikanth lingutla on 11/20/25.
//

import SwiftUI
import AppKit

enum NavigationTab: Hashable {
    case home
    case cockpit
    case discover
    case compare
    case run
    case code
    case notebox
    case learn
    case downloads
    case library
    case studyPackHistory
    case community
    case externalDevices
    case help
    case settings
}

struct ContentView: View {
    @State private var selectedTab: NavigationTab = .home
    // Keep the Monaco-backed tabs alive after first visit (no reload/flash).
    @State private var visitedCode = false
    @State private var visitedLearn = false
    @State private var visitedNotebox = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var showPersistenceWarning = DataStore.shared.persistenceDegraded
    @ObservedObject private var themeManager = ThemeManager.shared

    @ViewBuilder
    private var tabSwitch: some View {
        switch selectedTab {
        case .home:            HomeView(selectedTab: $selectedTab)
        case .cockpit:         CockpitView()
        case .discover:        DiscoverView()
        case .compare:         PromptLabView()
        case .run:             RunView()
        case .downloads:       DownloadsView()
        case .library:         LibraryView()
        case .studyPackHistory: StudyPackHistoryView()
        case .community:       CommunityView()
        case .externalDevices: ExternalDrivesView()
        case .help:            HelpView()
        case .settings:        SettingsView()
        case .code, .learn, .notebox:
            Color.clear   // rendered persistently below
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                // Sidebar header — restrained wordmark.
                HStack(spacing: Theme.Spacing.sm) {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Text("Kekasatori")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

                // Navigation list — native sidebar selection + accent tint.
                List(selection: $selectedTab) {
                    Section("Main") {
                        Label("Home", systemImage: "house")
                            .tag(NavigationTab.home)
                        Label("Cockpit", systemImage: "gauge.with.dots.needle.67percent")
                            .tag(NavigationTab.cockpit)
                        Label("Discover", systemImage: "sparkle.magnifyingglass")
                            .tag(NavigationTab.discover)
                        Label("Compare", systemImage: "rectangle.split.3x1")
                            .tag(NavigationTab.compare)
                        Label("Run", systemImage: "chart.bar.xaxis")
                            .tag(NavigationTab.run)
                        Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            .tag(NavigationTab.code)
                        Label("Notebox", systemImage: "book.pages")
                            .tag(NavigationTab.notebox)
                        Label("Learn", systemImage: "graduationcap")
                            .tag(NavigationTab.learn)
                        Label("Library", systemImage: "square.stack.3d.up")
                            .tag(NavigationTab.library)
                        Label("Study Packs", systemImage: "text.book.closed")
                            .tag(NavigationTab.studyPackHistory)
                        Label {
                            HStack(spacing: 6) {
                                Text("Community")
                                Text("BETA")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Theme.accent.opacity(0.18), in: Capsule())
                                    .foregroundStyle(Theme.accent)
                            }
                        } icon: {
                            Image(systemName: "person.3")
                        }
                        .tag(NavigationTab.community)
                        Label("Downloads", systemImage: "arrow.down.circle")
                            .tag(NavigationTab.downloads)
                    }

                    Section {
                        Label("Help", systemImage: "questionmark.circle")
                            .tag(NavigationTab.help)
                        Label("Settings", systemImage: "gearshape")
                            .tag(NavigationTab.settings)
                    } header: {
                        // Gold rule separating Main from Help / Settings.
                        SectionRule()
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                }
                .listStyle(.sidebar)
                .tint(Theme.accent)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
            ZStack {
                // Lightweight tabs — created/destroyed freely on switch.
                tabSwitch

                // WebView-heavy tabs (Monaco) — kept alive after first visit so
                // they don't reload/flash every time you navigate back.
                if visitedCode {
                    CodeBoxView(isActive: selectedTab == .code)
                        .opacity(selectedTab == .code ? 1 : 0)
                        .allowsHitTesting(selectedTab == .code)
                }
                if visitedLearn {
                    LearnView(isActive: selectedTab == .learn)
                        .opacity(selectedTab == .learn ? 1 : 0)
                        .allowsHitTesting(selectedTab == .learn)
                }
                if visitedNotebox {
                    NoteboxView(isActive: selectedTab == .notebox)
                        .opacity(selectedTab == .notebox ? 1 : 0)
                        .allowsHitTesting(selectedTab == .notebox)
                }
            }
            .onChange(of: selectedTab) { _, tab in
                // Clear any I-beam left set by a web-view editor we're navigating away from.
                NSCursor.arrow.set()
                if tab == .code { visitedCode = true }
                if tab == .learn { visitedLearn = true }
                if tab == .notebox { visitedNotebox = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCockpit)) { _ in
                selectedTab = .cockpit
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCode)) { _ in
                selectedTab = .code
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNotebox)) { _ in
                selectedTab = .notebox
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Persistent retro indicator: active workspace + compute dial state.
                ActiveContextBar()
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.bottom, 6)
            }
            .background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    themeManager.backgroundWash
                }
                .ignoresSafeArea()
            }
        }
        .tint(themeManager.accent)
        .task {
            await BinaryUpdateService.shared.ensureUpToDate()
        }
        .onAppear {
            if !hasSeenWelcome { showWelcome = true }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet {
                hasSeenWelcome = true
                showWelcome = false
            }
        }
        .alert("Library couldn’t be opened", isPresented: $showPersistenceWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Kekasatori couldn’t open its database, so it’s running in a temporary mode for this session — new study packs and downloads won’t be saved. Check that your disk isn’t full, then restart the app.")
        }
    }
}

private struct WelcomeSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Kekasatori")
                .font(.title2.weight(.semibold))

            Text("Turn videos, papers, and articles into study material.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                row("link", "Import a link",
                    "Paste a YouTube, paper, article, or book URL on the Home tab.")
                row("text.book.closed", "Generate study packs",
                    "Get transcripts, summaries, notes, flashcards, and mind maps.")
                row("bubble.left.and.bubble.right", "Ask the tutor",
                    "Enable Apple Intelligence, or add an API key in Settings → AI Providers for stronger answers.")
            }
            .padding(.vertical, Theme.Spacing.sm)

            Button("Get Started", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 460)
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ContentView()
}
