//
//  ArrivalInvalidateOverlay.swift
//  Todo train
//
//  到着の締め。着いた切符と次の切符を同じ画面に出し、検札印を押してから
//  次の切符を leading にスワイプしたときだけ発車する。検札では発車しない。
//

import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ArrivalInvalidateOverlay: View {
    let moment: PunctualityMoment
    /// Cover is still up — start already settled so dismiss *is* the reveal (no second entrance).
    var skipEnter: Bool = false
    var onClose: () -> Void
    var onStamp: (UUID, ArrivalAction) throws -> Void
    var onIssueInstant: (String, Int) throws -> ArrivalTicketFace
    var onLeadingBoard: (UUID) throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings

    @State private var deck = ArrivalDeck(reserved: nil)
    @State private var instantTitle = ""
    @State private var instantMinutes = EstimateHeuristic.defaultHighlightMinutes
    @State private var didSeedMinutes = false
    @State private var issueError = ""
    @State private var boardError = ""
    @State private var stampError = ""

    /// 0 hidden below → 1 settled and waiting.
    @State private var enter: CGFloat = 0
    /// 0…1 ink on the arrived ticket.
    @State private var impact: CGFloat = 0
    @State private var stampHaptic = 0
    @State private var boardDrag: CGFloat = 0

    private var arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)? {
        switch moment.kind {
        case .arrival(let title, let estimate, _, let punctuality):
            (title, max(estimate / 60, 1), punctuality)
        case .onTimeService:
            nil
        }
    }

    private var otherFaces: [ArrivalTicketFace] {
        let reservedID = deck.reserved?.id
        return sessionManager.openTicketsInHubOrder()
            .filter { $0.id != reservedID }
            .map {
                ArrivalTicketFace(
                    id: $0.id,
                    title: $0.title,
                    minutes: max($0.estimatedSeconds / 60, 1)
                )
            }
    }

    private var leadingIsPositiveX: Bool {
        layoutDirection == .leftToRight
    }

    private var boardHint: String {
        leadingIsPositiveX ? "右へスワイプして発車" : "左へスワイプして発車"
    }

    var body: some View {
        Group {
            if let arrival {
                scene(arrival: arrival)
            }
        }
        .onAppear {
            refreshReservation()
            seedMinutesIfNeeded()
        }
    }

    @ViewBuilder
    private func scene(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> some View {
        let scrim = 0.12 + 0.23 * Double(enter)

        ZStack {
            Color.black.opacity(scrim).ignoresSafeArea()

            GeometryReader { geo in
                let width = geo.size.width
                let footerBlock: CGFloat = deck.stampedFace == nil ? (deck.canStamp ? 108 : 128) : 92
                let choiceBlock: CGFloat = deck.stampedFace == nil ? 52 : 0
                let ticketBudget = max(180, geo.size.height - footerBlock - choiceBlock - 36)
                let arrivedTicket = min(
                    ticketBudget * 0.4,
                    MarsTicketSpec.height(forWidth: max(120, width - 88))
                )
                let nextTicket = min(
                    ticketBudget - arrivedTicket,
                    MarsTicketSpec.height(forWidth: max(120, width - 40))
                )

                VStack(alignment: .leading, spacing: 10) {
                    arrivedBlock(arrival: arrival)
                        .frame(height: arrivedTicket + 22, alignment: .top)
                    nextBlock
                        .frame(height: nextTicket + 22, alignment: .top)
                    if deck.stampedFace == nil {
                        choiceRow
                    }
                    if !stampError.isEmpty {
                        Text(stampError)
                            .font(.footnote)
                            .foregroundStyle(TrainTheme.signalRed)
                    }
                    if !boardError.isEmpty {
                        Text(boardError)
                            .font(.footnote)
                            .foregroundStyle(TrainTheme.signalRed)
                    }
                    Spacer(minLength: 0)
                    footer(punctuality: arrival.punctuality)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .offset(y: (1 - enter) * 28)
            .opacity(Double(max(0, enter)))

            if deck.picker == .otherTickets {
                otherTicketPicker
            }
            if deck.picker == .instant {
                instantTicketPicker
            }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: stampHaptic)
        .onAppear {
            announceIfNeeded(arrival: arrival)
            runEntrance()
        }
    }

    private func arrivedBlock(
        arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("到着")
            MarsTicketView(
                content: MarsTicketContent(title: arrival.title, minutes: arrival.minutes),
                titleReveal: 1
            )
            .padding(.horizontal, 24)
            .overlay {
                MarsTicketUsedMarks(
                    punctuality: arrival.punctuality,
                    stampSettled: impact
                )
                .padding(.horizontal, 24)
                .opacity(deck.stampedFace == nil ? 0 : 1)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomTrailing) {
                if deck.stampedFace == nil {
                    stampPress(punctuality: arrival.punctuality)
                        .padding(.trailing, 36)
                        .padding(.bottom, 10)
                }
            }
            .opacity(deck.stampedFace == nil ? 1 : 0.92)
        }
    }

    private var nextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("次の一本")
            nextCard
        }
    }

    @ViewBuilder
    private var nextCard: some View {
        if let face = deck.destination?.face {
            ZStack {
                if deck.stampedFace != nil {
                    boardBackdrop
                }
                swipeableNextTicket(face)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("次の一本 \(face.title) \(face.minutes)分")
            .accessibilityHint(deck.stampedFace == nil ? "検札すると発車できます" : boardHint)
        } else {
            RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                .background {
                    RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
                .aspectRatio(MarsTicketSpec.aspectRatio, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Text("予約なし")
                            .font(.headline)
                        Text("別の切符、または即時切符")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("予約なし。別の切符、または即時切符")
        }
    }

    private var boardBackdrop: some View {
        let leading = TicketStackLayout.leadingWidth(
            translationWidth: boardDrag,
            leadingIsPositiveX: leadingIsPositiveX
        )
        let progress = min(1, max(0, leading) / ArrivalDeck.boardDistance)
        return RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
            .fill(TrainTheme.rail)
            .overlay(alignment: leadingIsPositiveX ? .leading : .trailing) {
                Label("発車", systemImage: leadingIsPositiveX ? "arrow.right" : "arrow.left")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .opacity(progress)
            }
            .opacity(progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var choiceRow: some View {
        HStack(spacing: 8) {
            Button("別の切符") { deck.showOtherTickets() }
                .buttonStyle(.bordered)
                .tint(.white)
            Button("即時切符") { deck.showInstant() }
                .buttonStyle(.bordered)
                .tint(.white)
            if deck.reserved != nil, deck.destination?.action != .nextRide {
                Button("予約に戻す") { deck.selectNextRide() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private func footer(punctuality: ArrivalPunctuality) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if deck.stampedFace == nil {
            Button {
                commitStamp(punctuality: punctuality)
            } label: {
                Text("検札する")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MarsTicketSpec.stampBlue)
            .disabled(!deck.canStamp)
            .accessibilityHint(deck.canStamp ? "到着を締める。発車はしない" : "行き先が決まるまで押せません")
                if !deck.canStamp {
                    Text("行き先を選ぶと検札できます")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
            } else {
                Text(boardHint)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Button("閉じる", action: onClose)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.72))
    }

    private func stampPress(punctuality: ArrivalPunctuality) -> some View {
        let ink = stampInk(punctuality)
        return Button {
            commitStamp(punctuality: punctuality)
        } label: {
            VStack(spacing: 4) {
                Capsule()
                    .fill(ink.opacity(0.85))
                    .frame(width: 16, height: 22)
                Circle()
                    .strokeBorder(ink, lineWidth: 2.4)
                    .background(Circle().fill(Color.white.opacity(0.92)))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Text(stampCenterLabel(punctuality))
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundStyle(ink)
                    }
            }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!deck.canStamp)
        .opacity(deck.canStamp ? 1 : 0.38)
        .accessibilityHidden(true)
    }

    private var otherTicketPicker: some View {
        NavigationStack {
            List(otherFaces) { face in
                Button(face.title) {
                    deck.selectOther(face)
                }
            }
            .navigationTitle("別の切符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { deck.dismissPicker() }
                }
            }
            .overlay {
                if otherFaces.isEmpty {
                    Text("開いている切符がありません")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var instantTicketPicker: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("何をする？", text: $instantTitle)
                    .textFieldStyle(.roundedBorder)
                EstimateChips(
                    minutesOptions: EstimateChips.ticketPresets,
                    style: .plainMinutes,
                    selectedMinutes: instantMinutes,
                    onSelect: { instantMinutes = $0 }
                )
                if !issueError.isEmpty {
                    Text(issueError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button("発行") { issueInstant() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(20)
            .navigationTitle("即時切符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        issueError = ""
                        deck.dismissPicker()
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func swipeableNextTicket(_ face: ArrivalTicketFace) -> some View {
        let ticket = MarsTicketView(
            content: MarsTicketContent(title: face.title, minutes: face.minutes),
            titleReveal: 1
        )
        .offset(x: boardDrag)

        return Group {
            if deck.stampedFace != nil {
                ticket.highPriorityGesture(boardGesture)
            } else {
                ticket
            }
        }
    }

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    boardDrag = value.translation.width
                }
            }
            .onEnded { value in
                let ticketID = deck.boardTicketID(
                    translation: value.translation,
                    predictedEnd: value.predictedEndTranslation,
                    leadingIsPositiveX: leadingIsPositiveX
                )
                if let ticketID {
                    boardFromSwipe(ticketID: ticketID)
                } else {
                    withAnimation(.smooth(duration: 0.35)) {
                        boardDrag = 0
                    }
                }
            }
    }

    private func boardFromSwipe(ticketID: UUID) {
        do {
            try onLeadingBoard(ticketID)
            boardError = ""
        } catch {
            boardError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            withAnimation(.smooth(duration: 0.35)) {
                boardDrag = 0
            }
        }
    }

    private func refreshReservation() {
        let reserved = sessionManager.reservedNextTicket().map { ticket in
            ArrivalTicketFace(
                id: ticket.id,
                title: ticket.title,
                minutes: max(ticket.estimatedSeconds / 60, 1)
            )
        }
        deck.adoptReservation(reserved)
    }

    private func seedMinutesIfNeeded() {
        guard !didSeedMinutes else { return }
        didSeedMinutes = true
        instantMinutes = settings.lastIssuedEstimateMinutes ?? EstimateHeuristic.defaultHighlightMinutes
    }

    private func issueInstant() {
        do {
            let face = try onIssueInstant(instantTitle, instantMinutes)
            issueError = ""
            deck.selectInstant(face)
        } catch {
            issueError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runEntrance() {
        impact = 0
        if reduceMotion || skipEnter {
            enter = 1
            return
        }
        enter = 0
        withAnimation(MarsTicketSpec.ArrivalMotion.enter) {
            enter = 1
        }
    }

    private func stampInk(_ punctuality: ArrivalPunctuality) -> Color {
        switch punctuality {
        case .early: MarsTicketSpec.stampPurple
        case .onTime: MarsTicketSpec.stampBlue
        case .late, .notApplicable: MarsTicketSpec.stampBlue.opacity(0.9)
        }
    }

    private func stampCenterLabel(_ punctuality: ArrivalPunctuality) -> String {
        switch punctuality {
        case .onTime: "定時"
        case .early: "早着"
        case .late, .notApplicable: "到着"
        }
    }

    private func commitStamp(punctuality: ArrivalPunctuality) {
        guard let selection = deck.stampSelection() else { return }
        guard let sessionID = moment.arrivedSessionID else {
            stampError = "到着の記録が見つかりません"
            return
        }
        do {
            try onStamp(sessionID, selection.action)
        } catch {
            stampError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        stampError = ""
        boardDrag = 0
        deck.markStamped()
        stampHaptic += 1
        if reduceMotion {
            impact = 1
            return
        }
        withAnimation(MarsTicketSpec.ArrivalMotion.slam) {
            impact = 1
        } completion: {
            if punctuality == .onTime || punctuality == .early {
                stampHaptic += 1
            }
        }
    }

    private func accessibilityText(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> String {
        let head = Punctuality.arrivalHeadline(arrival.punctuality)
        if deck.canStamp {
            return "\(head)。\(arrival.title)。検札印を押してください"
        }
        return "\(head)。\(arrival.title)。行き先を選ぶか、閉じてください"
    }

    private func announceIfNeeded(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: accessibilityText(arrival: arrival))
        #endif
    }
}

/// Punch hole + small circular stamp (≤ ~1/5 of ticket).
struct MarsTicketUsedMarks: View {
    var punctuality: ArrivalPunctuality = .late
    var stampSettled: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let stampSize = min(geo.size.width, geo.size.height) * 0.28
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color.black.opacity(0.55 * stampSettled))
                    .frame(width: 11, height: 11)
                    .overlay {
                        Circle().strokeBorder(MarsTicketSpec.printInk.opacity(0.35), lineWidth: 0.5)
                    }
                    .offset(x: 10, y: geo.size.height * 0.42)

                stampDisk(size: stampSize)
                    .scaleEffect(0.72 + 0.28 * stampSettled)
                    .opacity(Double(stampSettled))
                    .offset(
                        x: geo.size.width * 0.55,
                        y: geo.size.height * 0.48
                    )
                    .rotationEffect(.degrees(-12))
            }
        }
        .allowsHitTesting(false)
    }

    private func stampDisk(size: CGFloat) -> some View {
        let ink: Color = {
            switch punctuality {
            case .early: MarsTicketSpec.stampPurple
            case .onTime: MarsTicketSpec.stampBlue
            case .late, .notApplicable: MarsTicketSpec.stampBlue.opacity(0.9)
            }
        }()
        return ZStack {
            Circle()
                .strokeBorder(ink.opacity(0.85), lineWidth: 2.2)
            Circle()
                .strokeBorder(ink.opacity(0.35), lineWidth: 0.8)
                .padding(4)
            VStack(spacing: 2) {
                Text("ありがとうございます")
                    .font(.system(size: 6, weight: .semibold, design: .default))
                    .foregroundStyle(ink.opacity(0.8))
                Text(stampCenterLabel)
                    .font(MarsTicketSpec.stampFont())
                    .foregroundStyle(ink)
            }
        }
        .frame(width: size, height: size)
    }

    private var stampCenterLabel: String {
        switch punctuality {
        case .onTime: "定時"
        case .early: "早着"
        case .late, .notApplicable: "到着"
        }
    }
}

#Preview("Arrival stamp") {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return ArrivalInvalidateOverlay(
        moment: PunctualityMoment(
            kind: .arrival(
                title: "週次レビューの下書き",
                estimateSeconds: 1_500,
                actualSeconds: 1_440,
                punctuality: .onTime
            )
        ),
        onClose: {},
        onStamp: { _, _ in },
        onIssueInstant: { title, minutes in
            ArrivalTicketFace(id: UUID(), title: title, minutes: minutes)
        },
        onLeadingBoard: { _ in }
    )
    .environment(manager)
    .environment(AppSettings.shared)
    .modelContainer(container)
}
