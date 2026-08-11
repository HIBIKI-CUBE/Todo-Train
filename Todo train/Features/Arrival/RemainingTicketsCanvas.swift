//
//  RemainingTicketsCanvas.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct RemainingTicketsCanvas: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let parent: Ticket
    let fromSessionID: UUID?

    @State private var rows: [Row] = [Row()]
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

                Section("残り切符") {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("切符の名前", text: $row.title)
                                .focused($focusedRowID, equals: row.id)

                            if !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                EstimateChips(
                                    minutesOptions: EstimateChips.ticketPresets,
                                    style: .plainMinutes,
                                    highlightedMinutes: row.estimatedMinutes ?? 30
                                ) { minutes in
                                    row.estimatedMinutes = minutes
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button("行を追加") {
                        let row = Row()
                        rows.append(row)
                        focusedRowID = row.id
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("切符を発行") {
                        issue()
                    }
                    .disabled(!canIssue)
                }
            }
            .onAppear {
                focusedRowID = rows.first?.id
            }
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
                fromSessionID: fromSessionID
            )
            dismiss()
        } catch {
            // Keep canvas open; user can retry.
        }
    }
}
