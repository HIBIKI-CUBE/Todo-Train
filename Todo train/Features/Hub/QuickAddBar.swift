//
//  QuickAddBar.swift
//  Todo train
//
//  Sheet-based quick add (Form + continuous add).
//

import SwiftUI
import SwiftData

struct QuickAddSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query private var allSessions: [WorkSession]

    @State private var title = ""
    @State private var pendingMinutes = 30
    @State private var showCustomEstimate = false
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var insertionPosition: TicketInsertionPosition = .end
    @State private var didAddOnce = false
    @State private var addPulse = 0
    @FocusState private var titleFocused: Bool

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedTitle.isEmpty
    }

    private var defaultTag: Tag? {
        allTags.first
    }

    private var estimateSuggestion: (minutes: Int, sampleCount: Int)? {
        let tagIDs: Set<UUID>? = {
            if selectedTagIDs.isEmpty {
                return defaultTag.map { [$0.id] }
            }
            return selectedTagIDs
        }()
        let samples = EstimateHeuristic.arrivedSamples(
            from: Array(allSessions),
            matchingAnyTagIDs: tagIDs
        )
        return EstimateHeuristic.suggestion(from: samples)
    }

    private var highlightedEstimateMinutes: Int {
        estimateSuggestion?.minutes ?? EstimateHeuristic.defaultHighlightMinutes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("何をする？", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.go)
                        .onSubmit {
                            addTicket(keepOpen: true)
                        }
                } footer: {
                    Text("見積もりチップをタップすると、タイトル入力済みならすぐ発行します。")
                }

                Section {
                    EstimateChips(
                        minutesOptions: EstimateChips.ticketPresets,
                        style: .plainMinutes,
                        highlightedMinutes: highlightedEstimateMinutes,
                        selectedMinutes: pendingMinutes
                    ) { minutes in
                        pendingMinutes = minutes
                        showCustomEstimate = false
                        // H-03: title ready → chip tap completes add.
                        if canAdd {
                            addTicket(keepOpen: true)
                        }
                    }

                    Button(showCustomEstimate ? "プリセットに戻る" : "任意の分を入力") {
                        showCustomEstimate.toggle()
                    }

                    if showCustomEstimate {
                        CustomEstimateInput(
                            minutes: $pendingMinutes,
                            highlightedMinutes: highlightedEstimateMinutes
                        )
                    }
                } header: {
                    Text("見積もり")
                } footer: {
                    if let suggestion = estimateSuggestion {
                        Text(EstimateHeuristic.caption(
                            minutes: suggestion.minutes,
                            sampleCount: suggestion.sampleCount
                        ))
                    } else {
                        Text("到着した切符の履歴から、よく使う分を強調します。")
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
                    } footer: {
                        Text("デフォルトは末尾。連続追加のあいだ選択は維持されます。")
                    }
                }

                Section {
                    if allTags.isEmpty {
                        Text("タグはまだありません。Hub の … → タグ から追加できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allTags, id: \.id) { tag in
                            Button {
                                toggleTag(tag.id)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(TagPalette.color(hex: tag.colorHex))
                                        .frame(width: 10, height: 10)
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTagIDs.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(TrainTheme.rail)
                                    }
                                }
                            }
                            .accessibilityAddTraits(selectedTagIDs.contains(tag.id) ? .isSelected : [])
                        }
                    }
                } header: {
                    Text("タグ")
                } footer: {
                    Text("任意。連続追加のあいだ選択は維持されます。")
                }
            }
            .navigationTitle("新しい切符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didAddOnce ? "完了" : "キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        addTicket(keepOpen: true)
                    }
                    .fontWeight(.semibold)
                    .disabled(!canAdd)
                }
            }
            .sensoryFeedback(.success, trigger: addPulse)
            .onAppear {
                pendingMinutes = highlightedEstimateMinutes
                if let defaultTag {
                    selectedTagIDs = [defaultTag.id]
                }
                DispatchQueue.main.async {
                    titleFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.remove(id)
        } else {
            selectedTagIDs.insert(id)
        }
    }

    private func addTicket(keepOpen: Bool) {
        guard canAdd else { return }

        let openOrdered = openTickets
        var orderedIDs = openOrdered.map(\.id)
        let insertAt = TicketSortOrdering.insertionIndex(
            openIDsOrdered: orderedIDs,
            position: insertionPosition
        )

        let ticket = Ticket(
            title: trimmedTitle,
            estimatedSeconds: pendingMinutes * 60,
            sortOrder: insertAt
        )
        ticket.tags = allTags.filter { selectedTagIDs.contains($0.id) }
        modelContext.insert(ticket)

        orderedIDs.insert(ticket.id, at: insertAt)
        let orders = TicketSortOrdering.normalizedOrders(forOrderedIDs: orderedIDs)
        for open in openOrdered {
            if let order = orders[open.id] {
                open.sortOrder = order
            }
        }
        ticket.sortOrder = orders[ticket.id] ?? insertAt

        do {
            try modelContext.save()
        } catch {
            // Keep sheet open; user can retry.
            return
        }

        didAddOnce = true
        addPulse += 1
        title = ""
        if keepOpen {
            DispatchQueue.main.async {
                titleFocused = true
            }
        } else {
            dismiss()
        }
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    return QuickAddSheet()
        .modelContainer(container)
}
