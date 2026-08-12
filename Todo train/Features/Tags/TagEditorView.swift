//
//  TagEditorView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct TagEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existing: Tag?

    @State private var name: String = ""
    @State private var colorHex: String = TagPalette.colors[0].hex
    @State private var tagPendingDelete: Tag?

    var body: some View {
        Form {
            Section("名前") {
                TextField("タグ名", text: $name)
                    .textInputAutocapitalization(.never)
            }

            Section("色") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(TagPalette.colors, id: \.hex) { swatch in
                        Button {
                            colorHex = swatch.hex
                        } label: {
                            Circle()
                                .fill(TagPalette.color(hex: swatch.hex))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if colorHex == swatch.hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                    }
                }
                .padding(.vertical, 4)
            }

            if existing != nil {
                Section {
                    Button("タグを削除", role: .destructive) {
                        tagPendingDelete = existing
                    }
                } footer: {
                    if let existing {
                        Text(TicketDeletion.tagDeleteFooter(ticketCount: existing.tickets.count))
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "タグを追加" : "タグを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            if let existing {
                name = existing.name
                colorHex = existing.colorHex
            }
        }
        .deletionAlert(
            item: $tagPendingDelete,
            prompt: { TicketDeletion.tagPrompt(for: $0) }
        ) { tag in
            deleteExisting(tag)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing {
            existing.name = trimmed
            existing.colorHex = colorHex
        } else {
            let nextOrder = nextSortOrder()
            let tag = Tag(name: trimmed, colorHex: colorHex, sortOrder: nextOrder)
            modelContext.insert(tag)
        }
        try? modelContext.save()
        dismiss()
    }

    private func deleteExisting(_ tag: Tag) {
        modelContext.delete(tag)
        try? modelContext.save()
        let remaining = (try? modelContext.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        TagOrdering.normalizeSortOrders(remaining)
        try? modelContext.save()
        dismiss()
    }

    private func nextSortOrder() -> Int {
        let descriptor = FetchDescriptor<Tag>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        let maxOrder = (try? modelContext.fetch(descriptor).first?.sortOrder) ?? -1
        return maxOrder + 1
    }
}
