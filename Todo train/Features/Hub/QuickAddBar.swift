//
//  QuickAddBar.swift
//  Todo train
//
//  Thumb-zone ticket desk: single (dismiss → Hub celebration) vs continuous dump
//  (speed first — selection haptic + undo only).
//

import SwiftUI
import SwiftData

struct QuickAddSheet: View {
    /// Single-issue handoff: Hub shows the ticket after this sheet dismisses.
    var onSingleIssued: ((TicketIssueEjectEvent) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query(sort: \Ticket.sortOrder) private var allTickets: [Ticket]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query private var allSessions: [WorkSession]

    @State private var title = ""
    @State private var pendingMinutes = 30
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var insertionPosition: TicketInsertionPosition = .end
    @State private var continuousDump = false
    @State private var didAddOnce = false
    @State private var addPulse = 0
    @State private var warnPulse = 0
    @State private var softHapticPulse = 0
    @State private var showInsertMenu = false
    @State private var showCustomEstimate = false
    @State private var undoPayload: UndoPayload?
    @State private var didSeedEstimate = false
    @FocusState private var titleFocused: Bool

    private struct UndoPayload: Equatable {
        let ticketID: UUID
        let title: String
        let minutes: Int
    }

    private var openTickets: [Ticket] {
        allTickets.filter(\.isOpen)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedTitle.isEmpty
    }

    private var estimateSuggestion: (minutes: Int, sampleCount: Int)? {
        let tagIDs: Set<UUID>? = selectedTagIDs.isEmpty ? nil : selectedTagIDs
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
            VStack(spacing: 0) {
                titleZone
                    .padding(.horizontal, TrainTheme.Space.lg)
                    .padding(.top, TrainTheme.Space.md)

                if let undoPayload {
                    undoBar(undoPayload)
                        .padding(.horizontal, TrainTheme.Space.lg)
                        .padding(.top, TrainTheme.Space.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                tagStrip
                    .padding(.top, TrainTheme.Space.md)

                Spacer(minLength: TrainTheme.Space.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(TrainTheme.platform)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                thumbRail
            }
            .navigationTitle("新しい切符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didAddOnce ? "完了" : "キャンセル") {
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: softHapticPulse)
            .sensoryFeedback(.warning, trigger: warnPulse)
            .confirmationDialog("挿入位置", isPresented: $showInsertMenu, titleVisibility: .visible) {
                Button("末尾（デフォルト）") { insertionPosition = .end }
                Button("先頭") { insertionPosition = .start }
                ForEach(openTickets, id: \.id) { ticket in
                    Button("「\(ticket.title)」の直後") {
                        insertionPosition = .after(ticket.id)
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("次に発行する切符の位置。連続追加のあいだ維持されます。")
            }
            .sheet(isPresented: $showCustomEstimate) {
                customEstimateSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                continuousDump = false
                if !didSeedEstimate {
                    pendingMinutes = highlightedEstimateMinutes
                    didSeedEstimate = true
                }
                DispatchQueue.main.async {
                    titleFocused = true
                }
            }
            .animation(TrainTheme.Motion.soft, value: undoPayload)
            .animation(TrainTheme.Motion.soft, value: continuousDump)
        }
        .presentationDetents(
            verticalSizeClass == .compact ? [.large] : [.medium, .large]
        )
        .presentationDragIndicator(.visible)
    }

    // MARK: - Zones

    private var titleZone: some View {
        TextField("何をする？", text: $title)
            .font(.title2.weight(.semibold))
            .focused($titleFocused)
            .submitLabel(.go)
            .onSubmit { submitFromReturn() }
            .padding(.horizontal, TrainTheme.Space.md)
            .padding(.vertical, TrainTheme.Space.lg)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .fill(TrainTheme.surface)
            )
    }

    private func undoBar(_ payload: UndoPayload) -> some View {
        HStack {
            Text("切符を発行しました")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("取り消す") {
                performUndo(payload)
            }
            .fontWeight(.semibold)
        }
        .padding(.horizontal, TrainTheme.Space.md)
        .padding(.vertical, TrainTheme.Space.sm)
        .background(
            Capsule(style: .continuous)
                .fill(TrainTheme.surface)
        )
    }

    private var tagStrip: some View {
        Group {
            if allTags.isEmpty {
                Text("タグは Hub の … → タグ から追加できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TrainTheme.Space.lg)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(allTags, id: \.id) { tag in
                                tagChip(tag)
                            }
                        }
                        .padding(.horizontal, TrainTheme.Space.lg)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("タグ")
    }

    private func tagChip(_ tag: Tag) -> some View {
        let selected = selectedTagIDs.contains(tag.id)
        return Button {
            toggleTag(tag.id)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(TagPalette.color(hex: tag.colorHex))
                    .frame(width: 8, height: 8)
                Text(tag.name)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected
                ? .regular.tint(TrainTheme.rail).interactive()
                : .regular.interactive(),
            in: .capsule
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(tag.name)
    }

    private var thumbRail: some View {
        VStack(spacing: TrainTheme.Space.sm) {
            HStack(alignment: .center, spacing: TrainTheme.Space.md) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(pendingMinutes)")
                        .font(.system(size: 56, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(TrainTheme.Motion.gaugeSnap, value: pendingMinutes)
                        .onLongPressGesture(minimumDuration: 0.45) {
                            showCustomEstimate = true
                        }
                        .accessibilityHint("長押しで任意の分を入力")
                    Text("分")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 6) {
                    Toggle(isOn: $continuousDump) {
                        Text("連続掃き出し")
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(TrainTheme.rail)
                    .accessibilityHint("オンでシートを開いたまま速く発行。オフで1枚発行して閉じ、Hubで切符を見せます")

                    if didAddOnce {
                        Text("発行 \(addPulse)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(TrainTheme.Motion.soft, value: addPulse)
                    }
                }
            }

            EstimateSnapGauge(
                minutes: $pendingMinutes,
                highlightedMinutes: highlightedEstimateMinutes,
                willIssue: { canAdd },
                onCommit: { commitFromGauge() },
                onLongPress: {
                    if !openTickets.isEmpty {
                        showInsertMenu = true
                    }
                }
            )
            .padding(.bottom, TrainTheme.Space.xs)
        }
        .padding(.horizontal, TrainTheme.Space.lg)
        .padding(.top, TrainTheme.Space.md)
        .padding(.bottom, TrainTheme.Space.sm)
        .background(TrainTheme.surface.ignoresSafeArea(edges: .bottom))
    }

    private var customEstimateSheet: some View {
        NavigationStack {
            Form {
                Section {
                    CustomEstimateInput(
                        minutes: $pendingMinutes,
                        highlightedMinutes: highlightedEstimateMinutes
                    )
                } footer: {
                    Text("ゲージの停泊以外の分。連続追加のあいだ維持されます。")
                }
            }
            .navigationTitle("任意の分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        showCustomEstimate = false
                        titleFocused = true
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Actions

    private func submitFromReturn() {
        guard canAdd else {
            warnPulse += 1
            return
        }
        commitIssue()
    }

    private func commitFromGauge() {
        guard canAdd else {
            titleFocused = true
            return
        }
        commitIssue()
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.remove(id)
        } else {
            selectedTagIDs.insert(id)
        }
    }

    private func commitIssue() {
        guard canAdd else { return }

        let issuedTitle = trimmedTitle
        let issuedMinutes = pendingMinutes

        let openOrdered = openTickets
        var orderedIDs = openOrdered.map(\.id)
        let insertAt = TicketSortOrdering.insertionIndex(
            openIDsOrdered: orderedIDs,
            position: insertionPosition
        )

        let ticket = Ticket(
            title: issuedTitle,
            estimatedSeconds: issuedMinutes * 60,
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
            return
        }

        didAddOnce = true
        addPulse += 1

        if continuousDump {
            undoPayload = UndoPayload(
                ticketID: ticket.id,
                title: issuedTitle,
                minutes: issuedMinutes
            )
            scheduleUndoExpiry(for: ticket.id)
            softHapticPulse += 1
            title = ""
            DispatchQueue.main.async {
                titleFocused = true
            }
        } else {
            onSingleIssued?(
                TicketIssueEjectEvent(title: issuedTitle, minutes: issuedMinutes)
            )
            dismiss()
        }
    }

    private func scheduleUndoExpiry(for ticketID: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if undoPayload?.ticketID == ticketID {
                undoPayload = nil
            }
        }
    }

    private func performUndo(_ payload: UndoPayload) {
        let match = allTickets.first(where: { $0.id == payload.ticketID })
            ?? openTickets.first(where: { $0.id == payload.ticketID })
        if let match {
            modelContext.delete(match)
            try? modelContext.save()
        }
        title = payload.title
        pendingMinutes = payload.minutes
        undoPayload = nil
        titleFocused = true
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    return QuickAddSheet(onSingleIssued: nil)
        .modelContainer(container)
}
