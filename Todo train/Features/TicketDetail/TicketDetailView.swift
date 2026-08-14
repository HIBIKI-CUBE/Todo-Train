//
//  TicketDetailView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct TicketDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DeletionUndoCenter.self) private var undoCenter
    @Environment(TicketMotionBridge.self) private var ticketMotion
    @Bindable var ticket: Ticket

    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query private var allSessions: [WorkSession]

    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showPauseLimitSheet = false

    private var canBoard: Bool {
        sessionManager.isInService
            && sessionManager.phase != .running
            && sessionManager.phase != .overtime
            && ticket.isOpen
    }

    private var isPaused: Bool {
        sessionManager.pausedSessions.contains { $0.ticket?.id == ticket.id }
    }

    private var parentTickets: [Ticket] {
        ticket.parentLineages.compactMap(\.parent)
    }

    private var childTickets: [Ticket] {
        ticket.childLineages.compactMap(\.child)
    }

    private var sortedSessions: [WorkSession] {
        ticket.sessions.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    private var estimateSuggestion: (minutes: Int, sampleCount: Int)? {
        let tagIDs = Set(ticket.tags.map(\.id))
        let samples = EstimateHeuristic.arrivedSamples(
            from: Array(allSessions),
            matchingAnyTagIDs: tagIDs.isEmpty ? nil : tagIDs
        )
        return EstimateHeuristic.suggestion(from: samples)
    }

    var body: some View {
        Form {
            Section("切符") {
                if ticket.isOpen {
                    TextField("タイトル", text: $ticket.title)
                    VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
                        Text("見積もり \(ticket.estimatedSeconds / 60) 分")
                            .font(.subheadline.weight(.medium))
                        EstimateChips(
                            minutesOptions: EstimateChips.ticketPresets,
                            style: .plainMinutes,
                            highlightedMinutes: estimateSuggestion?.minutes,
                            selectedMinutes: ticket.estimatedSeconds / 60
                        ) { minutes in
                            ticket.estimatedSeconds = minutes * 60
                        }
                        CustomEstimateInput(
                            minutes: Binding(
                                get: { ticket.estimatedSeconds / 60 },
                                set: { ticket.estimatedSeconds = CustomEstimate.clampMinutes($0) * 60 }
                            ),
                            highlightedMinutes: estimateSuggestion?.minutes
                        )
                    }
                    DatePicker(
                        "期限（任意）",
                        selection: Binding(
                            get: { ticket.dueDate ?? Date() },
                            set: { ticket.dueDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    if ticket.dueDate != nil {
                        Button("期限をクリア") {
                            ticket.dueDate = nil
                        }
                        .foregroundStyle(.secondary)
                    }
                    if let suggestion = estimateSuggestion {
                        Text(EstimateHeuristic.caption(
                            minutes: suggestion.minutes,
                            sampleCount: suggestion.sampleCount
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text(ticket.title)
                        .font(.body.weight(.medium))
                    Text("見積もり \(ticket.estimatedSeconds / 60) 分")
                        .foregroundStyle(.secondary)
                    if let dueDate = ticket.dueDate {
                        Text("期限 \(dueDateLabel(dueDate))")
                            .foregroundStyle(.secondary)
                    }
                    if let kind = ticket.closureKind {
                        Text(closureLabel(kind))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(closureColor(kind))
                    }
                }
                if isPaused {
                    Text("停車中")
                        .foregroundStyle(.orange)
                }
            }

            if ticket.isOpen || !ticket.tags.isEmpty {
                Section("タグ") {
                    if allTags.isEmpty && ticket.isOpen {
                        Text("タグ管理から作成できます")
                            .foregroundStyle(.secondary)
                    } else if ticket.isOpen {
                        ForEach(allTags, id: \.id) { tag in
                            Button {
                                toggleTag(tag)
                            } label: {
                                HStack {
                                    TagChipView(
                                        name: tag.name,
                                        colorHex: tag.colorHex,
                                        isSelected: ticket.tags.contains(where: { $0.id == tag.id }),
                                        isHighlighted: tag.sortOrder == 0
                                    )
                                    Spacer()
                                    if ticket.tags.contains(where: { $0.id == tag.id }) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        TagChipRow(tags: ticket.tags, maxVisible: 8)
                    }
                }
            }

            if !parentTickets.isEmpty || !childTickets.isEmpty {
                Section("乗り継ぎ") {
                    ForEach(parentTickets, id: \.id) { parent in
                        NavigationLink {
                            TicketDetailView(ticket: parent)
                        } label: {
                            Label {
                                Text(parent.title)
                            } icon: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }
                    }
                    ForEach(childTickets, id: \.id) { child in
                        NavigationLink {
                            TicketDetailView(ticket: child)
                        } label: {
                            HStack {
                                Label {
                                    Text(child.title)
                                } icon: {
                                    Image(systemName: "arrow.right")
                                }
                                if child.isOpen {
                                    Spacer()
                                    Text("開")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("セッション") {
                Text("記録 \(ticket.sessions.count) 回")
                let total = ticket.sessions.reduce(0.0) { partial, session in
                    partial + session.accumulatedActiveSeconds
                }
                Text("累計アクティブ \(Int(total / 60)) 分")
                    .foregroundStyle(.secondary)

                ForEach(sortedSessions, id: \.id) { session in
                    sessionRow(session)
                }
            }

            if ticket.isOpen {
                Section {
                    Button(isPaused ? "再乗車" : "発車") {
                        board()
                    }
                    .disabled(!canBoard)
                }
            }

            Section {
                Button("切符を削除", role: .destructive) {
                    deleteTicket()
                }
                .accessibilityHint(TicketDeletion.ticketDeleteFooter(ride: TicketDeletion.rideState(for: ticket)))
            } footer: {
                Text(TicketDeletion.ticketDeleteFooter(ride: TicketDeletion.rideState(for: ticket)))
            }
        }
        .navigationTitle("切符の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? modelContext.save()
        }
        .errorAlert(isPresented: $showError, message: errorMessage)
        .sheet(isPresented: $showPauseLimitSheet) {
            PauseLimitSheet(
                pendingTicket: ticket,
                onSlotFreedTryBoard: { board() }
            )
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: WorkSession) -> some View {
        let row = HStack {
            Text(Punctuality.displayLabel(for: session))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(sessionTimeLabel(session))
                .font(.caption.monospacedDigit())
            Spacer()
            Text("\(Int(session.accumulatedActiveSeconds / 60))分")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if session.endedAt != nil {
            row.deleteSwipeAction(accessibilityName: "この乗車記録") {
                deleteSession(session)
            }
        } else {
            row
        }
    }

    private func board() {
        do {
            ticketMotion.zoomSourceID = ticket.id
            try sessionManager.board(ticket: ticket)
        } catch let error as SessionError where error == .pauseLimitReached {
            showPauseLimitSheet = true
        } catch {
            ticketMotion.zoomSourceID = nil
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteTicket() {
        let title = ticket.title
        let record = DeletionUndo.captureTicket(ticket)
        do {
            try sessionManager.deleteTicket(ticket)
            undoCenter.offer(message: DeletionUndo.bannerMessage(ticketTitle: title)) {
                withAnimation {
                    try? sessionManager.restoreDeletedTicket(record)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteSession(_ session: WorkSession) {
        let title = ticket.title
        let remainingIDs = ticket.sessions.map(\.id)
        let deletesTicket = TicketDeletion.shouldDeleteOrphanTicket(
            remainingSessionIDs: remainingIDs,
            removing: session.id
        )
        do {
            if deletesTicket {
                let record = DeletionUndo.captureTicket(ticket)
                try sessionManager.deleteEndedSession(session)
                undoCenter.offer(
                    message: DeletionUndo.bannerMessage(
                        historyTicketTitle: title,
                        deletedTicketToo: true
                    )
                ) {
                    withAnimation {
                        try? sessionManager.restoreDeletedTicket(record)
                    }
                }
                dismiss()
            } else {
                let record = DeletionUndo.captureSession(session)
                try sessionManager.deleteEndedSession(session)
                undoCenter.offer(
                    message: DeletionUndo.bannerMessage(
                        historyTicketTitle: title,
                        deletedTicketToo: false
                    )
                ) {
                    withAnimation {
                        try? sessionManager.restoreDeletedSession(record)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func toggleTag(_ tag: Tag) {
        if let index = ticket.tags.firstIndex(where: { $0.id == tag.id }) {
            ticket.tags.remove(at: index)
        } else {
            ticket.tags.append(tag)
        }
        try? modelContext.save()
    }

    private func closureLabel(_ kind: ClosureKind) -> String {
        switch kind {
        case .arrived: "到着"
        case .partialDisembark: "途中下車"
        case .abandoned: "放棄"
        }
    }

    private func closureColor(_ kind: ClosureKind) -> Color {
        switch kind {
        case .arrived: .green
        case .partialDisembark: .orange
        case .abandoned: .red
        }
    }

    private func sessionTimeLabel(_ session: WorkSession) -> String {
        let date = session.endedAt ?? session.startedAt
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func dueDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
