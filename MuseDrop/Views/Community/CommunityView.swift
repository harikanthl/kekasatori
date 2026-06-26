//
//  CommunityView.swift
//  MuseDrop
//
//  The discovery wall: browse, search, and import study packs shared by others.
//  Backed by `CommunityProvider.shared` (a local stub today, Nostr+IPFS later).
//

import SwiftUI

struct CommunityView: View {
    @StateObject private var viewModel = CommunityViewModel()
    @State private var importingId: String?
    @State private var showImported = false
    @State private var showNewCommunity = false
    @State private var newCommunityName = ""
    @State private var newCommunitySummary = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                ScreenHeader(
                    title: "Community",
                    subtitle: "Discover and import study packs shared by others",
                    systemImage: "person.3"
                )

                controls

                if let message = viewModel.errorMessage, viewModel.posts.isEmpty {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Couldn't load the wall",
                        message: message
                    )
                } else if viewModel.posts.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(viewModel.posts) { post in
                            CommunityPostRow(
                                post: post,
                                isImporting: importingId == post.id,
                                onImport: { importPost(post) },
                                onUpvote: { viewModel.upvote(post) }
                            )
                        }
                    }
                }

                Spacer(minLength: Theme.Spacing.xxl)
            }
            .screenColumn()
            .padding(.top, Theme.Spacing.xxl)
        }
        .onAppear { viewModel.reload() }
        .alert("Imported to your library", isPresented: $showImported) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The study pack was added to your Study Packs.")
        }
        .sheet(isPresented: $showNewCommunity) { newCommunitySheet }
    }

    private var newCommunitySheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("New Community")
                .font(.title3.weight(.semibold))
            Text("An open, public space anyone can discover and post to.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Name (e.g. Linear Algebra)", text: $newCommunityName)
                .textFieldStyle(.roundedBorder)
            TextField("What's this community about?", text: $newCommunitySummary)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showNewCommunity = false }
                Button("Create") {
                    let name = newCommunityName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let summary = newCommunitySummary
                    showNewCommunity = false
                    newCommunityName = ""
                    newCommunitySummary = ""
                    Task { await viewModel.createCommunity(name: name, summary: summary) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(newCommunityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 380)
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                SearchField(placeholder: "Search community…", text: $viewModel.searchText)

                Button { viewModel.reload() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh the wall")
            }

            HStack(spacing: Theme.Spacing.md) {
                Picker("Community", selection: $viewModel.selectedCommunity) {
                    Text("Everyone").tag(Community?.none)
                    ForEach(viewModel.communities) { community in
                        Text(community.name).tag(Community?.some(community))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                Button { showNewCommunity = true } label: {
                    Label("New", systemImage: "plus")
                }
                .help("Create a new community")

                Picker("Subject", selection: $viewModel.selectedCategory) {
                    Text("All Subjects").tag(StudyCategory?.none)
                    ForEach(StudyCategory.allCases) { cat in
                        Label(cat.label, systemImage: cat.glyph).tag(StudyCategory?.some(cat))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Picker("Type", selection: $viewModel.selectedType) {
                    Text("All Types").tag(CommunityContentType?.none)
                    ForEach(CommunityContentType.allCases) { type in
                        Text(type.label).tag(CommunityContentType?.some(type))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 150)

                Spacer()
            }
        }
        .onChange(of: viewModel.searchText) { _, _ in viewModel.reload() }
        .onChange(of: viewModel.selectedType) { _, _ in viewModel.reload() }
        .onChange(of: viewModel.selectedCategory) { _, _ in viewModel.reload() }
        .onChange(of: viewModel.selectedCommunity) { _, _ in viewModel.reload() }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "person.3",
            title: viewModel.searchText.isEmpty ? "Nothing shared yet" : "No matching posts",
            message: viewModel.searchText.isEmpty
                ? "Share a study pack from the Study Packs tab to start the wall."
                : "Try a different search or type filter."
        )
    }

    private func importPost(_ post: CommunityPost) {
        importingId = post.id
        Task {
            let ok = await viewModel.importPost(post)
            importingId = nil
            if ok { showImported = true }
        }
    }
}

private struct CommunityPostRow: View {
    let post: CommunityPost
    let isImporting: Bool
    let onImport: () -> Void
    let onUpvote: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            icon

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(post.title.isEmpty ? "Untitled" : post.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: Theme.Spacing.sm)

                    StatusPill(
                        text: post.contentType.label,
                        systemImage: post.contentType.glyph,
                        color: .secondary
                    )
                }

                if !post.summary.isEmpty {
                    Text(post.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                if post.category != nil || !post.tags.isEmpty {
                    HStack(spacing: Theme.Spacing.xs + 2) {
                        if let category = post.category {
                            StatusPill(text: category.label, systemImage: category.glyph, color: Theme.accent)
                        }
                        ForEach(post.tags.prefix(5), id: \.self) { tag in
                            StatusPill(text: "#\(tag)", systemImage: "number", color: .secondary)
                        }
                    }
                }

                HStack(spacing: Theme.Spacing.md) {
                    Label(post.author.handle, systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Label(
                        post.createdAt.formatted(.relative(presentation: .named)),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                    Button(action: onUpvote) {
                        Label("\(post.upvotes)", systemImage: "arrow.up.heart")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Upvote")
                }
            }

            importButton
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) { isHovered = hovering }
        }
    }

    private var importButton: some View {
        Button(action: onImport) {
            if isImporting {
                ProgressView().controlSize(.small)
            } else {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isImporting)
        .help("Add this study pack to your library")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(.quaternary)
            Image(systemName: post.contentType.glyph)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
        }
        .frame(width: 56, height: 56)
    }
}
