//
//  CommunityComposeSheet.swift
//  MuseDrop
//
//  Compose form shown when sharing a study pack to the community wall. Lets the
//  user pick a subject category and which community to post to (or Everyone),
//  and create a new open community inline.
//

import SwiftUI

struct CommunityComposeSheet: View {
    let contentType: CommunityContentType
    let onPublish: (_ title: String, _ summary: String, _ tags: [String], _ category: StudyCategory, _ communityId: String?) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var summary: String
    @State private var tagsText: String = ""
    @State private var category: StudyCategory = .other
    @State private var communityId: String?

    @State private var communities: [Community] = []
    @State private var creatingCommunity = false
    @State private var newCommunityName = ""
    @State private var newCommunitySummary = ""
    @State private var isSavingCommunity = false

    init(
        initialTitle: String,
        initialSummary: String,
        contentType: CommunityContentType,
        onPublish: @escaping (String, String, [String], StudyCategory, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.contentType = contentType
        self.onPublish = onPublish
        self.onCancel = onCancel
        _title = State(initialValue: initialTitle)
        _summary = State(initialValue: initialSummary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Share to Community")
                    .font(.title2.weight(.semibold))
                Text("Publishes a copy others can import. Your mastery progress and notebook stay private.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                field("Title") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                field("Description") {
                    TextEditor(text: $summary)
                        .frame(height: 72)
                        .font(.body)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                }

                HStack(spacing: Theme.Spacing.md) {
                    field("Subject") {
                        Picker("Subject", selection: $category) {
                            ForEach(StudyCategory.allCases) { cat in
                                Label(cat.label, systemImage: cat.glyph).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    field("Community") {
                        Picker("Community", selection: $communityId) {
                            Text("Everyone").tag(String?.none)
                            ForEach(communities) { community in
                                Text(community.name).tag(String?.some(community.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    field(" ") {
                        Button {
                            creatingCommunity = true
                        } label: {
                            Label("New", systemImage: "plus")
                        }
                        .help("Create a new community")
                    }
                }

                field("Tags") {
                    TextField("deep-learning, kernels, attention", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Label(contentType.label, systemImage: contentType.glyph)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)

                Button("Publish") {
                    onPublish(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary.trimmingCharacters(in: .whitespacesAndNewlines),
                        Self.parseTags(tagsText),
                        category,
                        communityId
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 520)
        .task { communities = (try? await CommunityProvider.shared.communities()) ?? [] }
        .sheet(isPresented: $creatingCommunity) { createCommunitySheet }
    }

    private var createCommunitySheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("New Community")
                .font(.title3.weight(.semibold))
            Text("An open, public space anyone can discover and post to.")
                .font(.callout)
                .foregroundStyle(.secondary)

            field("Name") {
                TextField("e.g. Linear Algebra", text: $newCommunityName)
                    .textFieldStyle(.roundedBorder)
            }
            field("Description") {
                TextField("What's this community about?", text: $newCommunitySummary)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { creatingCommunity = false }
                Button("Create") { createCommunity() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(newCommunityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingCommunity)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 380)
    }

    private func createCommunity() {
        let name = newCommunityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingCommunity = true
        Task {
            let created = try? await CommunityProvider.shared.createCommunity(name: name, summary: newCommunitySummary)
            isSavingCommunity = false
            if let created {
                communities.insert(created, at: 0)
                communityId = created.id
                newCommunityName = ""
                newCommunitySummary = ""
                creatingCommunity = false
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private static func parseTags(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map(String.init)
    }
}
