//
//  QuickAddBar.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct QuickAddBar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var awaitingEstimate = false
    @State private var awaitingTags = false
    @State private var pendingMinutes = 30
    @State private var selectedTagIDs: Set<UUID> = []
    @FocusState private var titleFocused: Bool

    private var defaultTag: Tag? {
        allTags.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(headerTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("完了") {
                        if awaitingTags {
                            finishWithTags()
                        } else {
                            close()
                        }
                    }
                    .font(.subheadline)
                }

                if awaitingTags {
                    Text(title)
                        .font(.body)
                    Text("見積もり \(pendingMinutes)分")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if allTags.isEmpty {
                        Text("タグはスキップできます（タグ管理で追加）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowTagPicker(
                            tags: allTags,
                            selectedIDs: $selectedTagIDs,
                            highlightedID: defaultTag?.id
                        )
                    }

                    HStack {
                        Button("スキップ") {
                            selectedTagIDs = []
                            finishWithTags()
                        }
                        .buttonStyle(.bordered)

                        Button("追加") {
                            finishWithTags()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if awaitingEstimate {
                    Text(title)
                        .font(.body)
                    EstimateChips(
                        minutesOptions: EstimateChips.ticketPresets,
                        style: .plainMinutes,
                        highlightedMinutes: 30
                    ) { minutes in
                        pendingMinutes = minutes
                        awaitingEstimate = false
                        awaitingTags = true
                    }
                } else {
                    TextField("何をする？", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleFocused)
                        .submitLabel(.next)
                        .onSubmit {
                            submitTitle()
                        }
                }
            }
            .padding(16)
            .background(.regularMaterial)
        }
        .onAppear {
            titleFocused = true
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                resetDraft()
                DispatchQueue.main.async {
                    titleFocused = true
                }
            }
        }
    }

    private var headerTitle: String {
        if awaitingTags { return "タグ（任意）" }
        if awaitingEstimate { return "見積もりを選ぶ" }
        return "新しい切符"
    }

    private func submitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            close()
            return
        }
        title = trimmed
        awaitingEstimate = true
    }

    private func finishWithTags() {
        let nextOrder = nextSortOrder()
        let ticket = Ticket(
            title: title,
            estimatedSeconds: pendingMinutes * 60,
            sortOrder: nextOrder
        )
        let chosen = allTags.filter { selectedTagIDs.contains($0.id) }
        ticket.tags = chosen
        modelContext.insert(ticket)
        try? modelContext.save()

        resetDraft()
        titleFocused = true
    }

    private func nextSortOrder() -> Int {
        let descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate { $0.closedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let maxOrder = (try? modelContext.fetch(descriptor).first?.sortOrder) ?? -1
        return maxOrder + 1
    }

    private func resetDraft() {
        title = ""
        awaitingEstimate = false
        awaitingTags = false
        pendingMinutes = 30
        selectedTagIDs = []
        titleFocused = false
    }

    private func close() {
        resetDraft()
        isPresented = false
    }
}

private struct FlowTagPicker: View {
    let tags: [Tag]
    @Binding var selectedIDs: Set<UUID>
    var highlightedID: UUID?

    var body: some View {
        FlexibleTagWrap(tags: tags) { tag in
            Button {
                if selectedIDs.contains(tag.id) {
                    selectedIDs.remove(tag.id)
                } else {
                    selectedIDs.insert(tag.id)
                }
            } label: {
                TagChipView(
                    name: tag.name,
                    colorHex: tag.colorHex,
                    isSelected: selectedIDs.contains(tag.id),
                    isHighlighted: tag.id == highlightedID
                )
            }
            .buttonStyle(.plain)
        }
    }
}

/// Simple wrapping layout for tag chips without external deps.
private struct FlexibleTagWrap<Content: View>: View {
    let tags: [Tag]
    @ViewBuilder var content: (Tag) -> Content

    var body: some View {
        // Use LazyVGrid for predictable wrapping on compact widths.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(tags, id: \.id) { tag in
                content(tag)
            }
        }
    }
}
