//
//  ReorderView.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct ReorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]

    @State private var selectedTagID: UUID?
    @State private var minMinutes = 1
    @State private var maxMinutes = 60

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    var body: some View {
        ZStack {
            PlatformBackground()
            List {
                Section {
                    Picker("タグ", selection: $selectedTagID) {
                        Text("すべて").tag(UUID?.none)
                        ForEach(allTags, id: \.id) { tag in
                            Text(tag.name).tag(Optional(tag.id))
                        }
                    }

                    Stepper("最短 \(minMinutes) 分", value: $minMinutes, in: 1...60)
                    Stepper("最長 \(maxMinutes) 分", value: $maxMinutes, in: 1...60)

                    Text("一致しない切符は薄く表示されます。並べ替えは全行で可能です。自動ソートはありません。")
                        .font(.caption)
                        .foregroundStyle(TrainTheme.muted)
                } header: {
                    Text("フィルタ（強調のみ）")
                }
                .listRowBackground(Color.white.opacity(0.9))

                Section {
                    ForEach(openTickets, id: \.id) { ticket in
                        reorderRow(ticket)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onMove(perform: moveTickets)
                } header: {
                    Text("切符")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("並べ替え")
        .navigationBarTitleDisplayMode(.inline)
        .tint(TrainTheme.rail)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onChange(of: minMinutes) { _, newValue in
            if newValue > maxMinutes { maxMinutes = newValue }
        }
        .onChange(of: maxMinutes) { _, newValue in
            if newValue < minMinutes { minMinutes = newValue }
        }
    }

    @ViewBuilder
    private func reorderRow(_ ticket: Ticket) -> some View {
        let matches = matchesFilter(ticket)
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ticket.title)
                    .font(TrainTheme.TypeScale.ticketTitle())
                    .foregroundStyle(TrainTheme.ink)
                HStack(spacing: 8) {
                    Text("\(ticket.estimatedSeconds / 60)分")
                        .font(TrainTheme.TypeScale.meta())
                        .foregroundStyle(TrainTheme.muted)
                    if let dueDate = ticket.dueDate {
                        SignalBadge(kind: .due, customLabel: dueDateLabel(dueDate))
                    }
                }
                if !ticket.tags.isEmpty {
                    TagChipRow(tags: ticket.tags)
                }
            }
            Spacer()
            if !matches {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(TrainTheme.track)
            }
        }
        .opacity(matches ? 1 : 0.42)
        .ticketSurface(emphasized: matches && (selectedTagID != nil || minMinutes > 1 || maxMinutes < 60))
    }

    private func matchesFilter(_ ticket: Ticket) -> Bool {
        let minutes = ticket.estimatedSeconds / 60
        guard minutes >= minMinutes, minutes <= maxMinutes else { return false }
        if let selectedTagID {
            return ticket.tags.contains { $0.id == selectedTagID }
        }
        return true
    }

    private func moveTickets(from source: IndexSet, to destination: Int) {
        var ordered = openTickets
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, ticket) in ordered.enumerated() {
            ticket.sortOrder = index
        }
        try? modelContext.save()
    }

    private func dueDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    return NavigationStack {
        ReorderView()
            .modelContainer(container)
    }
}
