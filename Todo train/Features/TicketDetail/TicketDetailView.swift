//
//  TicketDetailView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct TicketDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Bindable var ticket: Ticket

    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]

    @State private var errorMessage = ""
    @State private var showError = false

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

    var body: some View {
        Form {
            Section("切符") {
                if ticket.isOpen {
                    TextField("タイトル", text: $ticket.title)
                    Stepper(
                        "見積もり \(ticket.estimatedSeconds / 60) 分",
                        value: Binding(
                            get: { ticket.estimatedSeconds / 60 },
                            set: { ticket.estimatedSeconds = min(max($0, 1), 60) * 60 }
                        ),
                        in: 1...60
                    )
                } else {
                    Text(ticket.title)
                        .font(.body.weight(.medium))
                    Text("見積もり \(ticket.estimatedSeconds / 60) 分")
                        .foregroundStyle(.secondary)
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
                    HStack {
                        Text(HistoryStats.outcomeLabel(session.outcome))
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
                }
            }

            if ticket.isOpen {
                Section {
                    Button(isPaused ? "再開" : "発車") {
                        board()
                    }
                    .disabled(!canBoard && !isPaused)
                }
            }
        }
        .navigationTitle("切符の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            try? modelContext.save()
        }
        .alert("発車できません", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func board() {
        do {
            try sessionManager.board(ticket: ticket)
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
}
