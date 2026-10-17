//
//  ArrivalInvalidateOverlay.swift
//  Todo train
//
//  奥から Hub、発車、灰色のぼかし、到着の印。上から順に操作する。
//  印では発車しない。発車は印のあと、Hub と同じ投げ。
//

import SwiftData
import SwiftUI
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

struct ArrivalInvalidateOverlay: View {
    let moment: PunctualityMoment
    /// Cover is still up — start already settled so dismiss *is* the reveal (no second entrance).
    var skipEnter: Bool = false
    var onClose: () -> Void
    var onStamp: (UUID, ArrivalAction?) throws -> Void
    var onLeadingBoard: (UUID) throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings
    @Environment(TicketMotionBridge.self) private var ticketMotion
    @AppStorage(PunctualityFirstTimeTips.sealStorageKey) private var sawSealTip = false
    @Namespace private var fallbackZoom

    @State private var deck = ArrivalDeck(reserved: nil)
    @State private var boardError = ""
    @State private var stampError = ""
    @State private var ceremonyVisible = true

    /// 0 hidden below → 1 settled and waiting.
    @State private var enter: CGFloat = 0
    /// 0…1 ink on the arrived ticket.
    @State private var impact: CGFloat = 0
    @State private var sealImpact: CGFloat = 0
    #if DEBUG
    @State private var previewSealTier: PunctualityJudgment.OnTimeSealTier?
    #endif
    @State private var stampSeated = false
    @State private var ticketNudge: CGFloat = 0
    @State private var phosphor: CGFloat = 0
    @State private var praise = ArrivalPraise.plain
    @State private var baseHaptic = 0
    @State private var praiseHaptic = 0
    @State private var sealHaptic = 0
    @State private var stampGeneration = 0
    @State private var choiceHaptic = 0
    @State private var openHaptic = 0

    /// Focus を閉じる zoom とは別の namespace。同じ namespace に source を足すと到着の瞬間に落ちる。
    private var zoomNamespace: Namespace.ID {
        fallbackZoom
    }

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

    private var destinationTicket: Ticket? {
        guard let id = deck.destination?.face.id else { return nil }
        return sessionManager.fetchTicket(id: id)
    }

    var body: some View {
        Group {
            if let arrival {
                scene(arrival: arrival)
            }
        }
        .onAppear {
            refreshReservation()
        }
    }

    @ViewBuilder
    private func scene(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> some View {
        ZStack {
            departureLayer

            if ceremonyVisible {
                ceremony(arrival: arrival)
                    .transition(.opacity)
            }

            if !ceremonyVisible, !boardError.isEmpty {
                Text(boardError)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainTheme.signalRed)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(reduceMotion ? nil : MarsTicketSpec.ArrivalMotion.exit, value: ceremonyVisible)
        .sheet(isPresented: pickerPresented(.otherTickets)) {
            otherTicketPicker
        }
        .sheet(isPresented: pickerPresented(.instant)) {
            QuickAddSheet { event in
                deck.selectInstant(
                    ArrivalTicketFace(
                        id: event.ticketID,
                        title: event.title,
                        minutes: event.minutes
                    )
                )
                choiceHaptic += 1
            }
        }
    }

    private func pickerPresented(_ picker: ArrivalDeck.Picker) -> Binding<Bool> {
        Binding(
            get: { deck.picker == picker },
            set: { isShown in
                if !isShown, deck.picker == picker {
                    deck.dismissPicker()
                }
            }
        )
    }

    @ViewBuilder
    private var departureLayer: some View {
        if let ticket = destinationTicket {
            GeometryReader { geo in
                let size = TrainLayout.presentedCardSize(overlayWidth: geo.size.width)
                let slot = CGRect(
                    x: (geo.size.width - size.width) / 2,
                    y: (geo.size.height - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
                HubTicketPresentLayer(
                    ticket: ticket,
                    size: size,
                    overlaySize: geo.size,
                    slotLocal: slot,
                    sourceTilt: 0,
                    isPuttingBack: false,
                    covers: [],
                    canBoard: deck.stampedFace != nil,
                    disabledReason: nil,
                    zoomNamespace: zoomNamespace,
                    onDismiss: onClose,
                    onHoldDragEnded: { finishDepartureDrag($0, ticketID: ticket.id) },
                    onOpenDetail: {},
                    onBoard: { boardFromSwipe(ticketID: ticket.id) },
                    onDelete: {},
                    showsEditingMenu: false
                )
            }
            .id(ticket.id)
            .allowsHitTesting(!ceremonyVisible && deck.stampedFace != nil)
            .accessibilityHidden(ceremonyVisible)
        }
    }

    private func ceremony(
        arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)
    ) -> some View {
        ZStack {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.4)
            }
            .ignoresSafeArea()

            GeometryReader { geo in
                let width = min(max(geo.size.width - 40, 120), 420)
                let ticketHeight = MarsTicketSpec.height(forWidth: width)
                ScrollView {
                    VStack(spacing: 12) {
                        arrivedTicket(arrival: arrival)
                            .frame(width: width, height: ticketHeight)
                        arrivalRideLog
                            .frame(width: width, alignment: .leading)
                        choiceColumn(punctuality: arrival.punctuality)
                            .frame(width: width, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .offset(y: (1 - enter) * 28)
        .opacity(Double(max(0, enter)))
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: baseHaptic)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: praiseHaptic)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: sealHaptic)
        .onAppear {
            applyArrivalPreviewIfNeeded(punctuality: arrival.punctuality)
            announceIfNeeded(arrival: arrival)
            speakOnTimeIfNeeded(punctuality: arrival.punctuality)
            runEntrance()
        }
    }

    private func arrivedTicket(
        arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)
    ) -> some View {
        MarsTicketView(
            content: MarsTicketContent(title: arrival.title, minutes: arrival.minutes),
            titleReveal: 1
        )
        .offset(y: ticketNudge)
        .overlay {
            ArrivalStampPhosphor(
                spread: praise.spread,
                amount: phosphor,
                color: phosphorColor
            )
            .allowsHitTesting(false)
        }
        .overlay {
            MarsTicketUsedMarks(
                punctuality: arrival.punctuality,
                stampSettled: impact,
                innerRingSolid: praise.innerRingSolid,
                sealTier: resolvedSealTier(for: arrival.punctuality),
                sealSeason: stampSeason,
                sealTimeOfDay: stampTimeOfDay,
                sealSettled: sealImpact
            )
            .opacity(impact > 0.01 ? 1 : 0)
            .allowsHitTesting(false)
        }
        .overlay {
            if impact < 0.99 {
                GeometryReader { geo in
                    let diameter = min(geo.size.width, geo.size.height) * 0.36
                    stampPress(punctuality: arrival.punctuality, diameter: diameter)
                        .position(
                            x: geo.size.width * 0.7,
                            y: geo.size.height * 0.62
                        )
                }
            }
        }
    }

    private func choiceColumn(punctuality: ArrivalPunctuality) -> some View {
        VStack(spacing: ArrivalChoiceMetrics.gap) {
            VStack(spacing: ArrivalChoiceMetrics.gap) {
                if let reserved = deck.reserved {
                    ArrivalChoiceSign(
                        index: "予約",
                        title: reserved.title,
                        selected: deck.destination?.action == .nextRide,
                        hint: "この切符を次の一本にします。乗車は始まりません。"
                    ) {
                        choose { deck.selectNextRide() }
                    }
                }
                ArrivalChoiceSign(
                    index: "別",
                    title: titledChoice(action: .otherTicket, fallback: "別の切符"),
                    selected: deck.destination?.action == .otherTicket,
                    discloses: true,
                    hint: "開いている切符の一覧を出します"
                ) {
                    choose(feedback: .open) { deck.showOtherTickets() }
                }
                ArrivalChoiceSign(
                    index: "即時",
                    title: titledChoice(action: .instantTicket, fallback: "即時切符"),
                    selected: deck.destination?.action == .instantTicket,
                    discloses: true,
                    hint: "新しい切符を発行します"
                ) {
                    choose(feedback: .open) { deck.showInstant() }
                }
                ArrivalChoiceSign(
                    index: "終",
                    title: "ここまで",
                    selected: deck.declinedNext,
                    hint: "次は発車しません"
                ) {
                    choose { deck.selectNoNext() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("行き先")

            if reduceMotion {
                ArrivalDismissPlate(title: "印を押す", hint: deck.canStamp ? "この到着を残します" : "行き先を決めると押せます") {
                    commitStamp(punctuality: punctuality)
                }
                .disabled(!deck.canStamp)
                .opacity(deck.canStamp ? 1 : 0.4)
            }
            ArrivalDismissPlate(title: "閉じる", hint: "印を残さずに閉じます", action: onClose)
                .padding(.top, 8)
            if !stampError.isEmpty {
                Text(stampError)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainTheme.signalRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sensoryFeedback(.selection, trigger: choiceHaptic)
        .sensoryFeedback(.impact(weight: .light), trigger: openHaptic)
    }

    private func titledChoice(action: ArrivalAction, fallback: String) -> String {
        guard deck.destination?.action == action, let title = deck.destination?.face.title else {
            return fallback
        }
        return title
    }

    private enum ChoiceFeedback {
        case selection
        case open
    }

    private func choose(_ update: () -> Void, feedback: ChoiceFeedback = .selection) {
        guard !deck.didStamp else { return }
        update()
        switch feedback {
        case .selection:
            choiceHaptic += 1
        case .open:
            openHaptic += 1
        }
    }

    private func stampPress(punctuality: ArrivalPunctuality, diameter: CGFloat) -> some View {
        let ink = stampInk(punctuality)
        return Button {
            commitStamp(punctuality: punctuality)
        } label: {
            ZStack {
                Circle().fill(ink.opacity(0.08))
                Circle().strokeBorder(ink, lineWidth: max(3, diameter * 0.045))
                Circle()
                    .strokeBorder(ink.opacity(0.35), lineWidth: 1)
                    .padding(diameter * 0.08)
                Text(stampCenterLabel(punctuality))
                    .font(.system(size: diameter * 0.24, weight: .bold, design: .default))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: diameter, height: diameter)
            .frame(minWidth: ArrivalChoiceMetrics.hit, minHeight: ArrivalChoiceMetrics.hit)
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
        }
        .buttonStyle(ArrivalStampButtonStyle(reduceMotion: reduceMotion, seated: stampSeated))
        .disabled(!deck.canStamp)
        .opacity(deck.canStamp ? 1 : 0.45)
        .accessibilityLabel(
            PunctualityPresentation.stampAccessibilityLabel(
                punctuality: punctuality,
                includesCornerSeal: false
            )
        )
        .accessibilityHint(deck.canStamp ? "印を押します" : "行き先を決めると押せます")
    }

    @ViewBuilder
    private var arrivalRideLog: some View {
        if let session = arrivedSession {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(PunctualityPresentation.rideLogLines(for: session).enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                if punctualityShowsSealTip {
                    Text(PunctualityFirstTimeTips.sealLine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .onAppear {
                            if !sawSealTip { sawSealTip = true }
                        }
                }
            }
        }
    }

    private var arrivedSession: WorkSession? {
        moment.arrivedSessionID.flatMap { sessionManager.fetchWorkSession(id: $0) }
    }

    private var stampSeason: PunctualityJudgment.StampSeason {
        let ended = arrivedSession?.endedAt ?? sessionManager.clock.now
        return PunctualityJudgment.stampSeason(at: ended)
    }

    private var stampTimeOfDay: PunctualityJudgment.StampTimeOfDay {
        let ended = arrivedSession?.endedAt ?? sessionManager.clock.now
        return PunctualityJudgment.stampTimeOfDay(at: ended)
    }

    private func resolvedSealTier(for punctuality: ArrivalPunctuality) -> PunctualityJudgment.OnTimeSealTier? {
        #if DEBUG
        if let previewSealTier { return previewSealTier }
        #endif
        guard punctuality == .onTime, let session = arrivedSession else { return nil }
        return Punctuality.judgment(for: session).sealTier
    }

    private var punctualityShowsSealTip: Bool {
        guard let arrival else { return false }
        return arrival.punctuality == .onTime && sealImpact > 0.5 && !sawSealTip
    }

    #if DEBUG
    private func applyArrivalPreviewIfNeeded(punctuality: ArrivalPunctuality) {
        guard let preview = sessionManager.arrivalUIPreviewStamp else { return }
        praise = ArrivalPraise(punctuality: preview.punctuality, alreadyDone: false, nextWasReserved: false, continuedFromStamp: false)
        impact = 1
        previewSealTier = preview.sealTier
        sealImpact = preview.sealTier == nil ? 0 : 1
        deck.markStamped()
        stampSeated = true
    }
    #else
    private func applyArrivalPreviewIfNeeded(punctuality: ArrivalPunctuality) {}
    #endif

    private var otherTicketPicker: some View {
        NavigationStack {
            List(otherFaces) { face in
                Button(face.title) {
                    deck.selectOther(face)
                    choiceHaptic += 1
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func finishDepartureDrag(_ value: DragGesture.Value, ticketID: UUID) -> TicketStackLayout.HoldRelease {
        let live = TicketStackLayout.holdOffset(rest: .zero, translation: value.translation)
        let action = TicketStackLayout.holdRelease(
            hold: live,
            translation: value.translation,
            predictedEnd: value.predictedEndTranslation,
            canBoard: deck.stampedFace != nil
        )
        switch action {
        case .board:
            boardFromSwipe(ticketID: ticketID)
        case .putBack:
            onClose()
        case .snap:
            break
        }
        return action
    }

    private func boardFromSwipe(ticketID: UUID) {
        ticketMotion.zoomSourceID = ticketID
        do {
            try onLeadingBoard(ticketID)
            boardError = ""
        } catch {
            boardError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        case .late, .notApplicable: MarsTicketSpec.stampBlue
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
        guard let choice = deck.stampChoice() else { return }
        let action: ArrivalAction? = switch choice {
        case .ticket(let destination): destination.action
        case .noNextTicket: nil
        }
        if moment.recordsWorkSessionStamp {
            guard let sessionID = moment.arrivedSessionID else {
                stampError = "到着の記録が見つかりません"
                return
            }
            do {
                try onStamp(sessionID, action)
            } catch {
                stampError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return
            }
        }
        StampSoundPlayer.playStampThud()
        stampError = ""
        deck.markStamped()
        praise = praise(for: punctuality)
        stampSeated = true
        if praise.count > 0 {
            praiseHaptic += 1
        } else {
            baseHaptic += 1
        }
        let returnsToHub = action == nil
        let onTime = punctuality == .onTime
        stampGeneration += 1
        let generation = stampGeneration
        if reduceMotion {
            impact = 1
            sealImpact = onTime ? 1 : 0
            phosphor = praise.count > 0 ? 1 : 0
            if onTime { sealHaptic += 1 }
            scheduleHold(generation: generation, returnsToHub: returnsToHub)
            return
        }
        withAnimation(MarsTicketSpec.ArrivalMotion.slam) {
            impact = 1
            phosphor = praise.count > 0 ? 1 : 0
            ticketNudge = MarsTicketSpec.ArrivalMotion.nudgeAmplitude
        } completion: {
            withAnimation(MarsTicketSpec.ArrivalMotion.slam) {
                ticketNudge = 0
            }
            if onTime {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard generation == stampGeneration else { return }
                    sealHaptic += 1
                    withAnimation(MarsTicketSpec.ArrivalMotion.descend) {
                        sealImpact = 1
                    }
                }
            }
            scheduleHold(generation: generation, returnsToHub: returnsToHub)
        }
    }

    private func praise(for punctuality: ArrivalPunctuality) -> ArrivalPraise {
        let session = moment.arrivedSessionID.flatMap { sessionManager.fetchWorkSession(id: $0) }
        return ArrivalPraise(
            punctuality: punctuality,
            alreadyDone: session?.overtimeResolution == .alreadyDone,
            nextWasReserved: deck.reserved != nil,
            continuedFromStamp: session?.startedFrom == .arrivalSwipe
                || session?.startedFrom == .passengerAlight
        )
    }

    private var phosphorColor: Color {
        switch praise.ink {
        case .onTime: MarsTicketSpec.stampBlue
        case .early: MarsTicketSpec.stampPurple
        case .arrival: TrainTheme.rail
        }
    }

    private func scheduleHold(generation: Int, returnsToHub: Bool) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(MarsTicketSpec.ArrivalMotion.stampHoldMilliseconds))
            guard generation == stampGeneration else { return }
            if returnsToHub {
                onClose()
            } else {
                withAnimation(reduceMotion ? nil : MarsTicketSpec.ArrivalMotion.exit) {
                    ceremonyVisible = false
                }
            }
        }
    }

    private func accessibilityText(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> String {
        let head = Punctuality.arrivalHeadline(arrival.punctuality)
        if let next = deck.destination?.face {
            return "\(head)、\(arrival.title)、次の一本 \(next.title)"
        }
        if deck.declinedNext {
            return "\(head)、\(arrival.title)、ここまで"
        }
        return "\(head)、\(arrival.title)"
    }

    private func announceIfNeeded(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: accessibilityText(arrival: arrival))
        #endif
    }

    private func speakOnTimeIfNeeded(punctuality: ArrivalPunctuality) {
        guard punctuality == .onTime else { return }
        CabinVoiceSpeaker.speakDriverLine(
            PunctualityPresentation.onTimeArrivalVoiceLine(),
            enabled: settings.cabinAnnouncementsEnabled
        )
    }
}

/// Punch hole + small circular stamp (≤ ~1/5 of ticket).
struct MarsTicketUsedMarks: View {
    var punctuality: ArrivalPunctuality = .late
    var stampSettled: CGFloat = 1
    var innerRingSolid: Bool = false
    var sealTier: PunctualityJudgment.OnTimeSealTier?
    var sealSeason: PunctualityJudgment.StampSeason = .spring
    var sealTimeOfDay: PunctualityJudgment.StampTimeOfDay = .afternoon
    var sealSettled: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let stampSize = min(geo.size.width, geo.size.height) * 0.28
            let seat = CGPoint(
                x: geo.size.width * 0.70,
                y: geo.size.height * 0.62 + MarsTicketSpec.ArrivalMotion.travel
            )
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color.black.opacity(0.55 * stampSettled))
                    .frame(width: 11, height: 11)
                    .overlay {
                        Circle().strokeBorder(MarsTicketSpec.printInk.opacity(0.35), lineWidth: 0.5)
                    }
                    .offset(x: 10, y: geo.size.height * 0.42)

                stampDisk(size: stampSize)
                    .scaleEffect(0.86 + 0.14 * stampSettled)
                    .opacity(Double(stampSettled))
                    .rotationEffect(.degrees(-12))
                    .position(seat)

                if let sealTier {
                    OnTimeCornerSealMark(
                        tier: sealTier,
                        season: sealSeason,
                        timeOfDay: sealTimeOfDay,
                        settled: sealSettled
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(
            PunctualityPresentation.stampAccessibilityLabel(
                punctuality: punctuality,
                includesCornerSeal: sealTier != nil && sealSettled > 0.5
            )
        )
    }

    private func stampDisk(size: CGFloat) -> some View {
        let ink: Color = {
            switch punctuality {
            case .early: MarsTicketSpec.stampPurple
            case .onTime: MarsTicketSpec.stampBlue
            case .late, .notApplicable: MarsTicketSpec.stampBlue
            }
        }()
        return ZStack {
            Circle()
                .strokeBorder(ink.opacity(0.9), lineWidth: 2.4)
            Circle()
                .strokeBorder(ink.opacity(innerRingSolid ? 0.95 : 0.35), lineWidth: innerRingSolid ? 2.2 : 0.8)
                .padding(size * 0.12)
            Text(stampCenterLabel)
                .font(MarsTicketSpec.stampFont())
                .foregroundStyle(ink)
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

/// HIG の最小タップ領域。行先票はこの高さより縮めない。
private enum ArrivalChoiceMetrics {
    static let hit: CGFloat = 44
    static let gap: CGFloat = 8
}

/// 駅名標の一行。板と押下でボタンだと分かる。選択は番号欄の反転と線の太さで、色だけに頼らない。
private struct ArrivalChoiceSign: View {
    var index: String
    var title: String
    var selected: Bool
    var discloses: Bool = false
    var hint: String
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Text(index)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selected ? Color.black : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 36, minHeight: 22)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                    .background {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(selected ? Color.white : Color.clear)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(Color.white.opacity(selected ? 1 : 0.85), lineWidth: selected ? 1.5 : 1)
                            }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.medium))
                        .tracking(StationSignMetrics.nameTracking(title, compact: false))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle()
                        .fill(TrainTheme.rail.opacity(selected ? 1 : 0.55))
                        .frame(height: selected ? 4 : 3)
                }

                if discloses {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: ArrivalChoiceMetrics.hit, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ArrivalPlateButtonStyle(selected: selected, reduceMotion: reduceMotion))
        .accessibilityLabel("\(index) \(title)")
        .accessibilityHint(hint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 行先ではない操作。同じ当たり判定で、路線帯は付けない。
private struct ArrivalDismissPlate: View {
    var title: String
    var hint: String
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(title, action: action)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: ArrivalChoiceMetrics.hit)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .buttonStyle(ArrivalPlateButtonStyle(selected: false, reduceMotion: reduceMotion))
            .accessibilityHint(hint)
    }
}

private struct ArrivalStampButtonStyle: ButtonStyle {
    var reduceMotion: Bool
    var seated: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: (!reduceMotion && (configuration.isPressed || seated)) ? MarsTicketSpec.ArrivalMotion.travel : 0)
            .animation(
                reduceMotion ? nil : MarsTicketSpec.ArrivalMotion.descend,
                value: configuration.isPressed || seated
            )
    }
}

private struct ArrivalStampPhosphor: View {
    var spread: ArrivalPraise.Spread
    var amount: CGFloat
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let seat = CGPoint(
                x: geo.size.width * 0.70,
                y: geo.size.height * 0.62 + MarsTicketSpec.ArrivalMotion.travel
            )
            let radius = spread == .paper
                ? max(geo.size.width, geo.size.height)
                : min(geo.size.width, geo.size.height) * 0.42
            RadialGradient(
                colors: [
                    color.opacity(0.9 * amount),
                    color.opacity(0.28 * amount),
                    color.opacity(0)
                ],
                center: .center,
                startRadius: 0,
                endRadius: radius
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(seat)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct ArrivalPlateButtonStyle: ButtonStyle {
    var selected: Bool
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(plateOpacity(pressed: configuration.isPressed)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(selected ? 1 : 0.62),
                        lineWidth: selected ? 2 : 1
                    )
            }
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : TrainTheme.Motion.pageSnap, value: configuration.isPressed)
    }

    private func plateOpacity(pressed: Bool) -> Double {
        if pressed { return selected ? 0.38 : 0.26 }
        return selected ? 0.18 : 0.10
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
        onLeadingBoard: { _ in }
    )
    .environment(manager)
    .environment(AppSettings.shared)
    .environment(TicketMotionBridge())
    .modelContainer(container)
}
