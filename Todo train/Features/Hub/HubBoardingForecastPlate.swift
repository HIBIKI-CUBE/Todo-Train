//
//  HubBoardingForecastPlate.swift
//  Todo train
//
//  Station plate under a lifted Hub ticket: printed 予定 vs 予測,
//  occupancy as a 駅名標-shaped 行先票 on the same board.
//

import SwiftData
import SwiftUI

struct HubBoardingForecastPlate: View {
    let ticket: Ticket
    var ticketWidth: CGFloat
    var plateHeight: CGFloat
    var playReveal: Bool = true

    @Query private var sessions: [WorkSession]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ArrivalForecastTraceLog.self) private var forecastLog
    @Environment(ArrivalForecastStore.self) private var forecastStore

    @State private var fillProgress: CGFloat = 0
    @State private var caretMinutes: CGFloat = 0
    @State private var scaleWindowSeconds: TimeInterval = TimeInterval(TimetableFit.markWindowMinutes * 60)
    @State private var showsScheduledClock = false
    @State private var showsPredictedMark = false
    @State private var showsDispatchChip = false
    @State private var zoomHaptic = 0
    @State private var crossHaptic = 0
    @State private var refinedMinutes: Int?
    @State private var inspectTrace: ArrivalForecastTrace?
    @State private var clockAnchor = Date()
    @State private var refineTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: clockAnchor, by: 15)) { timeline in
            let snapshot = displaySnapshot(at: timeline.date)
            plate(snapshot, at: timeline.date)
        }
        .sensoryFeedback(.selection, trigger: zoomHaptic)
        .sensoryFeedback(.impact(weight: .light), trigger: crossHaptic)
        .frame(width: ticketWidth, height: plateHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.55) {
            guard settings.developerToolsUnlocked else { return }
            inspectTrace = forecastLog.latest(matchingTitle: ticket.title) ?? forecastLog.traces.first
        }
        .onAppear {
            syncReveal(playReveal)
            startRefineIfNeeded()
        }
        .onChange(of: playReveal) { _, play in
            syncReveal(play)
            startRefineIfNeeded()
        }
        .onChange(of: ticket.id) { _, _ in
            refinedMinutes = nil
            refineTask?.cancel()
            refineTask = nil
            syncReveal(playReveal)
            startRefineIfNeeded()
        }
        .sheet(item: $inspectTrace) { trace in
            NavigationStack {
                DeveloperForecastTraceView(trace: trace)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { inspectTrace = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var timePointSize: CGFloat {
        plateHeight >= 96 ? 26 : 20
    }

    private var compactTimePointSize: CGFloat {
        plateHeight >= 96 ? 20 : 16
    }

    private func heuristicSnapshot(at now: Date) -> BoardingForecast.Snapshot {
        BoardingForecast.make(now: now, ticket: ticket, sessions: Array(sessions))
    }

    private func displaySnapshot(at now: Date) -> BoardingForecast.Snapshot {
        heuristicSnapshot(at: now).withPredictedMinutes(overlayMinutes(at: now), now: now)
    }

    private func overlayMinutes(at now: Date) -> Int? {
        switch forecastStore.lookup(ticket: ticket, sessions: Array(sessions), now: now) {
        case .hit(let minutes):
            return minutes
        case .miss:
            return refinedMinutes
        }
    }

    @ViewBuilder
    private func plate(_ snapshot: BoardingForecast.Snapshot, at now: Date) -> some View {
        let occupancy = occupancyInstrument(at: now)
        let dispatch = TimetableFit.boardingDispatch(
            fit: occupancy.fit,
            now: now,
            scheduledArrival: snapshot.scheduledArrival,
            predictedArrival: snapshot.predictedArrival
        )
        let clearance = TimetableFit.boardingClearance(
            fit: occupancy.fit,
            now: now,
            scheduledArrival: snapshot.scheduledArrival,
            predictedArrival: snapshot.predictedArrival
        )
        let zoomed = clearance.zooms
        let tight = zoomed || !occupancy.rows.isEmpty
        VStack(alignment: .leading, spacing: tight ? 3 : 5) {
            clockDigits(
                time: BoardingForecast.timeString(from: snapshot.scheduledArrival),
                foot: BoardingForecast.durationLabel(minutes: snapshot.scheduledMinutes),
                visible: showsScheduledClock,
                pointSize: tight ? compactTimePointSize : timePointSize,
                compact: tight,
                ink: zoomed ? LEDPhosphor.heat : LEDPhosphor.on
            )
            track(
                snapshot,
                occupancy: occupancy,
                dispatch: dispatch,
                clearance: clearance,
                at: now
            )
            if !zoomed, let row = occupancy.rows.first {
                OccupancyDestinationSign(
                    row: row,
                    surface: .station(heat: false),
                    compact: true,
                    actionTitle: occupancy.actionTitle,
                    action: occupancy.action
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, tight ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background { StationSignHousing(rimLit: true, heat: zoomed) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(snapshot, occupancy: occupancy))
        .modifier(OccupancyAccessAction(title: occupancy.actionTitle, action: occupancy.action))
        .allowsHitTesting(settings.developerToolsUnlocked || occupancy.actionTitle != nil)
    }

    private func occupancyInstrument(at now: Date) -> (
        fit: TimetableFitSnapshot,
        rows: [TimetableOccupancyRow],
        actionTitle: String?,
        action: (() -> Void)?
    ) {
        let fit = sessionManager.timetableFit(at: now)
        let rows = TimetableFit.occupancyRows(
            fit: fit,
            now: now,
            calendar: sessionManager.calendar
        )
        if fit.currentOccupancy?.isAdopted == true {
            return (fit, rows, TimetableCopy.unadopt, { sessionManager.unadoptCurrentOccurrence() })
        }
        if fit.currentOccupancy?.isAdopted == false {
            return (fit, rows, TimetableCopy.adopt, { sessionManager.adoptCurrentNoticeThisTime() })
        }
        return (fit, rows, nil, nil)
    }

    private func clockDigits(
        time: String,
        foot: String?,
        visible: Bool,
        pointSize: CGFloat,
        compact: Bool,
        ink: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(time)
                .font(.system(size: pointSize, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let foot {
                Text(foot)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold, design: .default))
                    .foregroundStyle(ink.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func track(
        _ snapshot: BoardingForecast.Snapshot,
        occupancy: (
            fit: TimetableFitSnapshot,
            rows: [TimetableOccupancyRow],
            actionTitle: String?,
            action: (() -> Void)?
        ),
        dispatch: TimetableDispatchScale,
        clearance: TimetableClearance,
        at now: Date
    ) -> some View {
        let window = max(scaleWindowSeconds, 1)
        let quiet = TimeInterval(TimetableFit.markWindowMinutes * 60)
        let zoomX = CGFloat(quiet / window)
        let pinch = clearance.zooms
        let onColor = pinch ? LEDPhosphor.heat : LEDPhosphor.on
        let offColor = pinch ? LEDPhosphor.heatOff : LEDPhosphor.off
        let revealedMinutes = Double(snapshot.scheduledScaleMinutes) * fillProgress
        let fill = TicketDurationScale.filled(exactMinutes: revealedMinutes)
        let fillBrightness = fillBrightness(snapshot)
        let caretBrightness = caretBrightness(snapshot)
        let worldMarks = TimetableFit.occupancyMarks(
            fit: occupancy.fit,
            now: now,
            windowSeconds: quiet
        )
        let viewMarks = TimetableFit.occupancyMarks(
            fit: occupancy.fit,
            now: now,
            windowSeconds: window
        )
        let caretWorldX = min(1, caretMinutes / CGFloat(TicketDurationScale.maxMinutes))
        let caretViewX = min(1, caretMinutes * 60 / window)
        let fillWorld = min(1, revealedMinutes / Double(TicketDurationScale.maxMinutes))
        let currentView = viewMarks.first(where: \.isCurrent)
        let nextView = viewMarks.first(where: { !$0.isCurrent })
        let chipRow = occupancy.rows.first
        let trackHeight: CGFloat = pinch ? 54 : 17
        return ZStack(alignment: .top) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: MarsTicketSpec.durationTrackGap) {
                        ForEach(0..<TicketDurationScale.cellCount, id: \.self) { index in
                            trackCell(
                                amount: TicketDurationScale.cellFillAmount(index: index, fill: fill),
                                brightness: fillBrightness,
                                on: onColor,
                                off: offColor
                            )
                        }
                    }
                    .frame(width: geo.size.width, height: 10)
                    .offset(y: 7)

                    occupancyWorldMarks(
                        marks: worldMarks,
                        fillWorld: fillWorld,
                        overrun: clearance == .overrun,
                        width: geo.size.width
                    )

                    if snapshot.hasPrediction {
                        TimetableCaret()
                            .fill(onColor.opacity(caretBrightness))
                            .frame(width: 9, height: 7)
                            .position(x: geo.size.width * caretWorldX, y: 4)
                            .opacity(showsPredictedMark ? 1 : 0)
                    }
                }
                .frame(width: geo.size.width, height: 17, alignment: .topLeading)
                .scaleEffect(x: zoomX, anchor: .topLeading)
            }
            .frame(height: 17)
            .clipped()
            .accessibilityHidden(true)

            if snapshot.hasPrediction, let predicted = snapshot.predictedArrival {
                GeometryReader { geo in
                    Text(BoardingForecast.timeString(from: predicted))
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(onColor.opacity(caretBrightness))
                        .position(
                            x: min(geo.size.width - 26, max(26, geo.size.width * caretViewX + 18)),
                            y: 5
                        )
                        .opacity(showsPredictedMark ? 1 : 0)
                }
                .frame(height: 17)
                .allowsHitTesting(false)
            }

            if let chipRow, pinch {
                GeometryReader { geo in
                    let placement = destinationPlacement(
                        width: geo.size.width,
                        current: currentView,
                        next: nextView
                    )
                    OccupancyDestinationSign(
                        row: chipRow,
                        surface: .glass,
                        compact: true,
                        liveEnd: occupancy.fit.currentOccupancy?.endsAt
                            ?? occupancy.fit.nextOccupancy?.startsAt,
                        now: now,
                        actionTitle: occupancy.actionTitle,
                        action: occupancy.action
                    )
                    .frame(width: placement.width)
                    .position(x: placement.centerX, y: 38)
                    .opacity(showsDispatchChip ? 1 : 0)
                }
            }
        }
        .frame(height: trackHeight)
    }

    private func destinationPlacement(
        width: CGFloat,
        current: TimetableOccupancyMark?,
        next: TimetableOccupancyMark?
    ) -> (width: CGFloat, centerX: CGFloat) {
        let minWidth = min(width, 208)
        if let current, current.span > 0 {
            let signWidth = min(width, max(minWidth, width * current.span))
            let center = width * (current.span / 2)
            return (signWidth, clampedCenter(center, width: width, signWidth: signWidth))
        }
        if let next {
            let signWidth = min(width, 232)
            return (signWidth, clampedCenter(width * next.position, width: width, signWidth: signWidth))
        }
        return (minWidth, width / 2)
    }

    private func clampedCenter(_ raw: CGFloat, width: CGFloat, signWidth: CGFloat) -> CGFloat {
        let half = signWidth / 2
        return min(width - half, max(half, raw))
    }

    @ViewBuilder
    private func occupancyWorldMarks(
        marks: [TimetableOccupancyMark],
        fillWorld: Double,
        overrun: Bool,
        width: CGFloat
    ) -> some View {
        ForEach(marks) { mark in
            let gate = mark.isCurrent ? mark.position + mark.span : mark.position
            if mark.isCurrent, mark.span > 0 {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(width: max(8, width * mark.span), height: 10)
                    .position(x: width * (mark.position + mark.span / 2), y: 12)
            }
            if overrun, fillWorld > mark.position {
                Rectangle()
                    .fill(LEDPhosphor.heat.opacity(0.28))
                    .frame(width: max(2, width * (min(1, fillWorld) - mark.position)), height: 10)
                    .offset(x: width * mark.position, y: 7)
            }
            Capsule()
                .fill((overrun ? LEDPhosphor.heat : LEDPhosphor.on).opacity(mark.isAdopted ? 0.95 : 0.55))
                .frame(width: mark.isAdopted ? 3 : 2, height: 12)
                .position(x: width * min(1, max(0, gate)), y: 12)
        }
    }

    private func trackCell(amount: Double, brightness: Double, on: Color, off: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 0.7, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(off)
            if amount >= 1 {
                shape.fill(on.opacity(brightness))
            } else if amount > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(on.opacity(brightness))
                        .frame(width: geo.size.width * amount)
                }
                .clipShape(shape)
            }
        }
    }

    /// Longer mark is brighter. Same phosphor — not a late signal.
    private func fillBrightness(_ snapshot: BoardingForecast.Snapshot) -> Double {
        guard let predicted = snapshot.predictedMinutes else { return 0.92 }
        return snapshot.scheduledMinutes >= predicted ? 0.92 : 0.55
    }

    private func caretBrightness(_ snapshot: BoardingForecast.Snapshot) -> Double {
        guard let predicted = snapshot.predictedMinutes else { return 0.92 }
        return predicted > snapshot.scheduledMinutes ? 0.92 : 0.62
    }

    private func accessibilityLabel(
        _ snapshot: BoardingForecast.Snapshot,
        occupancy: (
            fit: TimetableFitSnapshot,
            rows: [TimetableOccupancyRow],
            actionTitle: String?,
            action: (() -> Void)?
        )
    ) -> String {
        var parts = [
            "\(BoardingForecast.scheduledHeadline) \(BoardingForecast.timeString(from: snapshot.scheduledArrival))",
            BoardingForecast.durationLabel(minutes: snapshot.scheduledMinutes),
        ]
        if let predicted = snapshot.predictedArrival, let minutes = snapshot.predictedMinutes {
            parts.append(
                "\(BoardingForecast.predictedHeadline) \(BoardingForecast.predictedTimeString(from: predicted))"
            )
            parts.append(
                BoardingForecast.predictedCaption(minutes: minutes, sampleCount: snapshot.sampleCount)
            )
        }
        parts.append(contentsOf: occupancy.rows.map(\.spokenLine))
        return parts.joined(separator: "。")
    }

    private func syncReveal(_ play: Bool) {
        let snapshot = displaySnapshot(at: .now)
        let fit = sessionManager.timetableFit(at: .now)
        let dispatch = TimetableFit.boardingDispatch(
            fit: fit,
            now: .now,
            scheduledArrival: snapshot.scheduledArrival,
            predictedArrival: snapshot.predictedArrival
        )
        let clearance = TimetableFit.boardingClearance(
            fit: fit,
            now: .now,
            scheduledArrival: snapshot.scheduledArrival,
            predictedArrival: snapshot.predictedArrival
        )
        let scheduledMinutes = CGFloat(snapshot.scheduledScaleMinutes)
        let predictedMinutes = snapshot.predictedScaleMinutes.map { CGFloat($0) }
        let quietWindow = TimeInterval(TimetableFit.markWindowMinutes * 60)

        if !play {
            var parked = Transaction()
            parked.animation = nil
            withTransaction(parked) {
                fillProgress = 0
                caretMinutes = scheduledMinutes
                scaleWindowSeconds = quietWindow
                showsScheduledClock = false
                showsPredictedMark = false
                showsDispatchChip = false
            }
            return
        }

        if reduceMotion {
            var parked = Transaction()
            parked.animation = nil
            withTransaction(parked) {
                fillProgress = 1
                caretMinutes = predictedMinutes ?? scheduledMinutes
                scaleWindowSeconds = clearance.zooms ? dispatch.windowSeconds : quietWindow
                showsScheduledClock = true
                showsPredictedMark = snapshot.hasPrediction
                showsDispatchChip = clearance.zooms
            }
            return
        }

        let motion = MarsTicketSpec.HubStack.TimetableReveal.self
        var parked = Transaction()
        parked.animation = nil
        withTransaction(parked) {
            fillProgress = 0
            caretMinutes = scheduledMinutes
            scaleWindowSeconds = quietWindow
            showsScheduledClock = false
            showsPredictedMark = false
            showsDispatchChip = false
        }
        withAnimation(.easeOut(duration: motion.fillDuration)) {
            fillProgress = 1
            showsScheduledClock = true
        }
        if snapshot.hasPrediction, let predictedMinutes {
            withAnimation(
                .easeOut(duration: motion.caretAppearDuration).delay(motion.caretAppearDelay)
            ) {
                showsPredictedMark = true
            }
            withAnimation(
                .smooth(duration: motion.caretTravelDuration).delay(motion.caretTravelDelay)
            ) {
                caretMinutes = predictedMinutes
            }
        }
        guard clearance.zooms else { return }
        withAnimation(.smooth(duration: motion.zoomDuration).delay(motion.zoomDelay)) {
            scaleWindowSeconds = dispatch.windowSeconds
            showsDispatchChip = true
        }
        Task { @MainActor in
            let nanos = UInt64((motion.zoomDelay + motion.zoomDuration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard playReveal else { return }
            zoomHaptic += 1
            let occupancyOffset = dispatch.occupancyEdge?.timeIntervalSince(.now) ?? .greatestFiniteMagnitude
            let predictedOffset = TimeInterval((predictedMinutes ?? scheduledMinutes) * 60)
            if predictedOffset >= occupancyOffset {
                crossHaptic += 1
            }
        }
    }

    private func startRefineIfNeeded() {
        guard playReveal, refineTask == nil else { return }
        if let cached = overlayMinutes(at: .now) {
            refinedMinutes = cached
        }
        refineTask = Task { @MainActor in
            await refineIfNeeded()
        }
    }

    private func refineIfNeeded() async {
        guard playReveal else { return }
        let sessionList = Array(sessions)
        guard let context = BoardingForecast.forecastContext(
            ticket: ticket,
            sessions: sessionList,
            now: .now
        ) else {
            forecastLog.record(.skipped(title: ticket.title))
            return
        }
        let minutes = await forecastStore.refresh(
            ticket: ticket,
            sessions: sessionList,
            now: .now
        )
        guard !Task.isCancelled else { return }
        let alreadyShowing = overlayMinutes(at: .now)
        refinedMinutes = minutes
        guard let minutes, minutes != context.medianMinutes, minutes != alreadyShowing else { return }
        let fractionMinutes = CGFloat(minutes)
        if reduceMotion {
            caretMinutes = fractionMinutes
        } else {
            withAnimation(.smooth(duration: 0.35)) {
                caretMinutes = fractionMinutes
            }
        }
    }
}

private struct TimetableCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct OccupancyAccessAction: ViewModifier {
    var title: String?
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let title, let action {
            content.accessibilityAction(named: title, action)
        } else {
            content
        }
    }
}

#Preview {
    let (container, manager) = HubPreviewSeed.make(scenario: .inService)
    let ticket = Ticket(title: "レビュー", estimatedSeconds: 30 * 60)
    container.mainContext.insert(ticket)
    return ZStack {
        Color(uiColor: .systemGroupedBackground)
        HubBoardingForecastPlate(ticket: ticket, ticketWidth: 320, plateHeight: 101)
    }
    .environment(manager)
    .environment(AppSettings.shared)
    .environment(ArrivalForecastTraceLog.shared)
    .environment(ArrivalForecastStore.shared)
    .modelContainer(container)
}
