//
//  RemainingTicketsCanvas.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct RemainingTicketsCanvas: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]

    let parent: Ticket
    let fromSessionID: UUID?

    @State private var rows: [Row] = [Row()]
    @State private var insertionPosition: TicketInsertionPosition = .end
    @State private var errorMessage = ""
    @State private var showError = false
    @FocusState private var focusedRowID: UUID?

    private struct Row: Identifiable, Equatable {
        let id: UUID
        var title: String
        var estimatedMinutes: Int?

        init(id: UUID = UUID(), title: String = "", estimatedMinutes: Int? = nil) {
            self.id = id
            self.title = title
            self.estimatedMinutes = estimatedMinutes
        }
    }

    private var openTickets: [Ticket] {
        allTickets.filter { $0.isOpen && $0.id != parent.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("途中下車: \(parent.title)")
                        .font(.headline)
                    Text("残りの切符を書き出す")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("切符の名前", text: $row.title)
                                .focused($focusedRowID, equals: row.id)

                            if !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                EstimateChips(
                                    minutesOptions: EstimateChips.ticketPresets,
                                    style: .plainMinutes,
                                    highlightedMinutes: row.estimatedMinutes,
                                    selectedMinutes: row.estimatedMinutes
                                ) { minutes in
                                    row.estimatedMinutes = minutes
                                }

                                CustomEstimateInput(
                                    minutes: Binding(
                                        get: { row.estimatedMinutes ?? 30 },
                                        set: { row.estimatedMinutes = CustomEstimate.clampMinutes($0) }
                                    ),
                                    highlightedMinutes: row.estimatedMinutes
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .deleteSwipeAction(accessibilityName: rowTitle(row)) {
                            removeRow(id: row.id)
                        }
                    }
                    .onDelete { offsets in
                        removeRows(at: offsets)
                    }

                    Button("行を追加") {
                        let row = Row()
                        rows.append(row)
                        focusedRowID = row.id
                    }
                } header: {
                    Text("残り切符")
                } footer: {
                    if !canIssue && rows.contains(where: {
                        !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }) {
                        Text("見積もりを選んでから発行できます。")
                    }
                }

                if !openTickets.isEmpty {
                    Section {
                        InsertPositionPicker(
                            openTickets: openTickets,
                            position: $insertionPosition
                        )
                    } header: {
                        Text("挿入位置")
                    }
                }
            }
            .navigationTitle("乗り継ぎ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("残りなしで閉じる") {
                        dismiss()
                    }
                    .accessibilityLabel("残りの切符なしで閉じる")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("切符を発行") {
                        issue()
                    }
                    .disabled(!canIssue)
                }
            }
            .alert("発行できませんでした", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                focusedRowID = rows.first?.id
            }
        }
    }

    private func rowTitle(_ row: Row) -> String {
        let trimmed = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "この行" : trimmed
    }

    private func removeRow(id: UUID) {
        rows.removeAll { $0.id == id }
        if rows.isEmpty {
            rows = [Row()]
        }
    }

    private func removeRows(at offsets: IndexSet) {
        rows.remove(atOffsets: offsets)
        if rows.isEmpty {
            rows = [Row()]
        }
    }

    private var canIssue: Bool {
        rows.contains {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ($0.estimatedMinutes ?? 0) > 0
        }
    }

    private func issue() {
        let drafts = rows.compactMap { row -> TicketLineageService.Draft? in
            let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let minutes = row.estimatedMinutes, minutes > 0 else { return nil }
            return .init(title: title, estimatedSeconds: minutes * 60)
        }
        do {
            try TicketLineageService.issueTransferTickets(
                from: parent,
                drafts: drafts,
                modelContext: modelContext,
                fromSessionID: fromSessionID,
                insertionPosition: insertionPosition
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
