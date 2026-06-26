//
//  HelpView.swift
//  MuseDrop
//
//  In-app guide: what each tab does and how to do the common things. Plain,
//  scannable documentation — no network, no external links required.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                ScreenHeader(
                    title: "Help & Guide",
                    subtitle: "What each tab does, and how to get things done",
                    systemImage: "questionmark.circle"
                )

                intro

                tabsSection
                howToSection
                tipsSection

                Spacer(minLength: Theme.Spacing.xxl)
            }
            .screenColumn(maxWidth: 820)
            .padding(.vertical, Theme.Spacing.xxl)
        }
    }

    // MARK: - Intro

    private var intro: some View {
        Text("Kekasatori turns anything you can watch or read — videos, papers, articles, books — into a study session with AI tools. Paste a link on **Home**, pick how you want to use it, and the app builds a study pack you can revisit, master, and share.")
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }

    // MARK: - Tabs

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader("What each tab does", systemImage: "sidebar.left", tint: Theme.accent)

            VStack(spacing: 0) {
                ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, tab in
                    HelpTabRow(icon: tab.icon, title: tab.title, detail: tab.detail)
                    if index < Self.tabs.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .cardSurface()
        }
    }

    private static let tabs: [(icon: String, title: String, detail: String)] = [
        ("house", "Home", "Your starting point. Paste any link into the command bar and choose a mode — Stream, Research, or Download. Recent links sit just below."),
        ("square.stack.3d.up", "Library", "Everything you've downloaded — audio and video — ready to play, study, or organize."),
        ("text.book.closed", "Study Packs", "The study materials the app generates from each session: summaries, tutor chat, mind maps, notebooks, canvas. Track mastery, pin favorites, export, or share."),
        ("person.3", "Community  ·  Beta", "Discover and share study packs on a decentralized network — no account, no server. Browse by subject or community, upvote, and import others' packs."),
        ("arrow.down.circle", "Downloads", "Active and queued downloads with live progress. Finished items move to your Library."),
        ("questionmark.circle", "Help", "This guide."),
        ("gearshape", "Settings", "Themes, default download formats, AI providers (for the tutor and podcasts), math animations, library location, and data management.")
    ]

    // MARK: - How-to

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader("How to…", systemImage: "list.number", tint: Theme.accent)

            VStack(spacing: Theme.Spacing.md) {
                HelpGuide(icon: "play.circle", title: "Stream & study a video", steps: [
                    "On Home, pick **Stream**.",
                    "Paste a video link — or tap the search icon to find one on YouTube.",
                    "Choose **Stream Audio** or **Stream Video**.",
                    "The player opens with study tools; nothing is saved to disk."
                ])
                HelpGuide(icon: "arrow.down.circle", title: "Download audio or video", steps: [
                    "On Home, pick **Download** and paste a link.",
                    "Choose **Audio** (MP3/AAC/WAV) or **Video** (MP4).",
                    "Watch progress in **Downloads**; the file lands in **Library** when done."
                ])
                HelpGuide(icon: "doc.text.magnifyingglass", title: "Study a paper, article, or book", steps: [
                    "On Home, pick **Research**.",
                    "Paste an arXiv / PubMed / DOI / PDF link or any article URL — or **Choose PDF** / drop a PDF.",
                    "Multi-chapter books and docs sites are crawled and combined into one document.",
                    "The reader opens with the same study tools as the player."
                ])
                HelpGuide(icon: "sparkles", title: "Use the AI study tools", steps: [
                    "In the player or reader, open the study panel for: Tutor chat, Mind map, Notebook, Canvas, and the Pomodoro focus timer.",
                    "Cloud tutor needs an API key in **Settings → AI Providers**.",
                    "On macOS 26 with Apple Intelligence, on-device models work with no key."
                ])
                HelpGuide(icon: "waveform.circle", title: "Make a podcast from a paper", steps: [
                    "Open a paper in the reader, then the **More (…)** menu → **Make Podcast…**.",
                    "Pick a page range; a multi-speaker audio podcast is generated.",
                    "Add your Google Gemini key in **Settings → AI Providers** first."
                ])
                HelpGuide(icon: "rectangle.3.group", title: "Track mastery", steps: [
                    "Open **Study Packs** and use the mastery board.",
                    "Drag a pack across the Shu → Ha → Ri stages as you learn it.",
                    "Badges in the Library reflect each pack's mastery."
                ])
                HelpGuide(icon: "person.3", title: "Share & use the Community (Beta)", steps: [
                    "In **Study Packs**, open a row's menu → **Share to Community…**.",
                    "Pick a **Subject** and a **Community** (or Everyone) — or create a new community inline.",
                    "On the **Community** tab, filter by subject/community, **Import** packs, and upvote.",
                    "It's decentralized (Nostr + IPFS); the first share installs a small networking component."
                ])
                HelpGuide(icon: "shippingbox", title: "Export or import a pack", steps: [
                    "In **Study Packs**, use **Export Pack…** to save a portable .kekapack file.",
                    "Use **Import Pack…** to load one shared with you — works fully offline."
                ])
            }
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader("Good to know", systemImage: "lightbulb", tint: Theme.accent)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                tip("Press ⌘V to paste a link straight into the Home command bar.")
                tip("Stream mode never writes video to disk — great for a quick study pass.")
                tip("Your notebook and mastery progress stay private; they are never shared to the Community.")
                tip("Community posts live on public relays, so availability can vary — your own posts are re-broadcast automatically.")
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            Text(.init(text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Components

private struct HelpTabRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }
}

private struct HelpGuide: View {
    let icon: String
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 20, height: 20)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                        Text(.init(step))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
