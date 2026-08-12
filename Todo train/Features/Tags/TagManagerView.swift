//
//  TagManagerView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct TagManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]

    @State private var editorMode: EditorMode?
    @State private var tagPendingDelete: Tag?

    private enum EditorMode: Identifiable {
        case create
        case edit(Tag)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let tag): tag.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            if tags.isEmpty {
                Text("タグはまだありません。追加して切符に付けられます。先頭のタグが新規追加時の候補になります。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tags, id: \.id) { tag in
                    Button {
                        editorMode = .edit(tag)
                    } label: {
                        HStack {
                            TagChipView(name: tag.name, colorHex: tag.colorHex)
                            Spacer()
                            if tag.sortOrder == 0 {
                                Text("デフォルト候補")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .deleteSwipeAction(accessibilityName: tag.name) {
                        tagPendingDelete = tag
                    }
                }
                .onMove(perform: moveTags)
            }
        }
        .navigationTitle("タグ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = .create
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            NavigationStack {
                switch mode {
                case .create:
                    TagEditorView()
                case .edit(let tag):
                    TagEditorView(existing: tag)
                }
            }
        }
        .deletionAlert(item: $tagPendingDelete, prompt: { TicketDeletion.tagPrompt(for: $0) }) { tag in
            deleteTag(tag)
        }
    }

    private func moveTags(from source: IndexSet, to destination: Int) {
        var ordered = Array(tags)
        ordered.move(fromOffsets: source, toOffset: destination)
        TagOrdering.normalizeSortOrders(ordered)
        try? modelContext.save()
    }

    private func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        try? modelContext.save()
        let remaining = (try? modelContext.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        TagOrdering.normalizeSortOrders(remaining)
        try? modelContext.save()
    }
}
