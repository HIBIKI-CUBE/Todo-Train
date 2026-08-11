//
//  QuickAddBar.swift
//  Todo train
//

import SwiftUI
import SwiftData

struct QuickAddBar: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var awaitingEstimate = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(awaitingEstimate ? "見積もりを選ぶ" : "新しい切符")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("完了") {
                        close()
                    }
                    .font(.subheadline)
                }

                if awaitingEstimate {
                    Text(title)
                        .font(.body)
                    EstimateChips(
                        minutesOptions: EstimateChips.ticketPresets,
                        style: .plainMinutes,
                        highlightedMinutes: 30
                    ) { minutes in
                        createTicket(minutes: minutes)
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
                title = ""
                awaitingEstimate = false
                DispatchQueue.main.async {
                    titleFocused = true
                }
            }
        }
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

    private func createTicket(minutes: Int) {
        let nextOrder = nextSortOrder()
        let ticket = Ticket(
            title: title,
            estimatedSeconds: minutes * 60,
            sortOrder: nextOrder
        )
        modelContext.insert(ticket)
        try? modelContext.save()

        title = ""
        awaitingEstimate = false
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

    private func close() {
        title = ""
        awaitingEstimate = false
        titleFocused = false
        isPresented = false
    }
}
