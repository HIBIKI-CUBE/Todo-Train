//
//  HubBoardingForecastPlate.swift
//  Todo train
//
//  Station plate under a lifted Hub ticket: printed 予定 vs 予測.
//  Fill grows as 予定; the caret travels to the forecast so the two stay distinct.
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

    private var showsDurationFoot: Bool {
        plateHeight >= 88
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
        let zoomed = dispatch.zooms
        let tight = zoomed || !occupancy.rows.isEmpty
        VStack(alignment: .leading, spacing: tight ? 3 : 5) {
            clocks(snapshot, compact: tight)
            track(
                snapshot,
                occupancy: occupancy,
                dispatch: dispatch,
                at: now
            )
            if zoomed {
                dispatchCaption(occupancy)
            } else if !occupancy.rows.isEmpty {
                TimetableOccupancyMeter(
                    rows: occupancy.rows,
                    marks: [],
                    chrome: .inverted,
                    showsRail: false,
                    compact: true
                ) {
                    if let title = occupancy.actionTitle, let action = occupancy.action {
                        Button(title, action: action)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LEDPhosphor.on)
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .accessibilityHint(TimetableCopy.thisTime)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, tight ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background { StationSignHousing(rimLit: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(snapshot, occupancy: occupancy))
        .modifier(OccupancyAccessAction(title: occupancy.actionTitle, action: occupancy.action))
        .allowsHitTesting(settings.developerToolsUnlocked || occupancy.actionTitle != nil)
    }

    @ViewBuilder
    private func dispatchCaption(
        _ occupancy: (
            fit: TimetableFitSnapshot,
            rows: [TimetableOccupancyRow],
            actionTitle: String?,
            action: (() -> Void)?
        )
    ) -> some View {
        if let row = occupancy.rows.first {
            HStack(spacing: 8) {
                Text(row.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LEDPhosphor.on.opacity(0.78))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let title = occupancy.actionTitle, let action = occupancy.action {
                    Button(title, action: action)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LEDPhosphor.on)
                        .buttonStyle(.plain)
                        .accessibilityHint(TimetableCopy.thisTime)
                }
            }
        }
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

    @ViewBuilder
    private func clocks(_ snapshot: BoardingForecast.Snapshot, compact: Bool) -> some View {
        let pointSize = compact ? compactTimePointSize : timePointSize
        let showFoot = compact ? false : showsDurationFoot
        if snapshot.hasPrediction,
           let predicted = snapshot.predictedArrival,
           let predictedMinutes = snapshot.predictedMinutes {
            HStack(alignment: .top, spacing: 12) {
                clockColumn(
                    headline: BoardingForecast.scheduledHeadline,
                    time: BoardingForecast.timeString(from: snapshot.scheduledArrival),
                    foot: BoardingForecast.durationLabel(minutes: snapshot.scheduledMinutes),
                    visible: showsScheduledClock,
                    pointSize: pointSize,
                    showFoot: showFoot
                )
                clockColumn(
                    headline: BoardingForecast.predictedHeadline,
                    time: BoardingForecast.predictedTimeString(from: predicted),
                    foot: BoardingForecast.predictedCaption(
                        minutes: predictedMinutes,
                        sampleCount: snapshot.sampleCount
                    ),
                    visible: showsPredictedMark,
                    pointSize: pointSize,
                    showFoot: showFoot
                )
            }
        } else {
            clockColumn(
                headline: BoardingForecast.scheduledHeadline,
                time: BoardingForecast.timeString(from: snapshot.scheduledArrival),
                foot: showFoot
                    ? BoardingForecast.durationLabel(minutes: snapshot.scheduledMinutes)
                    : nil,
                visible: showsScheduledClock,
                pointSize: pointSize,
                showFoot: showFoot
            )
            .frame(maxWidth: .infinity)
        }
    }

    private func clockColumn(
        headline: String,
        time: String,
        foot: String?,
        visible: Bool,
        pointSize: CGFloat,
        showFoot: Bool
    ) -> some View {
        VStack(alignment: .center, spacing: 1) {
            Text(headline)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(LEDPhosphor.on.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(time)
                .font(.system(size: pointSize, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(LEDPhosphor.on)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if showFoot, let foot {
                Text(foot)
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(LEDPhosphor.on.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 6)
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
        at now: Date
    ) -> some View {
        let window = max(scaleWindowSeconds, 1)
        let revealedMinutes = Double(snapshot.scheduledScaleMinutes) * fillProgress
        let fillFraction = min(1, revealedMinutes * 60 / window)
        let fill = TicketDurationScale.filled(exactMinutes: fillFraction * Double(TicketDurationScale.maxMinutes))
        let fillBrightness = fillBrightness(snapshot)
        let caretBrightness = caretBrightness(snapshot)
        let caretX = min(1, caretMinutes * 60 / window)
        let marks = TimetableFit.occupancyMarks(
            fit: occupancy.fit,
            now: now,
            windowSeconds: window
        )
        let currentSpan = marks.first(where: \.isCurrent)?.span ?? 0
        let nextMark = marks.first(where: { !$0.isCurrent })?.position
        let chipX: Double? = {
            if currentSpan > 0 { return currentSpan }
            return nextMark
        }()
        let chipRow = occupancy.rows.first
        let chipDrops = chipX.map { abs(caretX - $0) < 0.1 } ?? false
        let trackHeight: CGFloat = dispatch.zooms ? 36 : 17
        return ZStack(alignment: .top) {
            HStack(spacing: MarsTicketSpec.durationTrackGap) {
                ForEach(0..<TicketDurationScale.cellCount, id: \.self) { index in
                    trackCell(
                        amount: TicketDurationScale.cellFillAmount(index: index, fill: fill),
                        brightness: fillBrightness
                    )
                }
            }
            .frame(height: 10)
            .padding(.top, 7)

            if currentSpan > 0, dispatch.zooms {
                GeometryReader { geo in
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .frame(width: max(8, geo.size.width * currentSpan), height: 10)
                        .position(x: geo.size.width * currentSpan / 2, y: 12)
                }
            }

            if snapshot.hasPrediction {
                GeometryReader { geo in
                    TimetableCaret()
                        .fill(LEDPhosphor.on.opacity(caretBrightness))
                        .frame(width: 9, height: 7)
                        .position(x: geo.size.width * caretX, y: 4)
                        .opacity(showsPredictedMark ? 1 : 0)
                }
            }

            if let chipX, let chipRow, dispatch.zooms {
                GeometryReader { geo in
                    OccupancyDispatchChip(
                        row: chipRow,
                        end: occupancy.fit.currentOccupancy?.endsAt
                            ?? occupancy.fit.nextOccupancy?.startsAt
                            ?? now,
                        now: now
                    )
                    .position(
                        x: min(geo.size.width - 54, max(54, geo.size.width * chipX)),
                        y: chipDrops ? 28 : 22
                    )
                    .opacity(showsDispatchChip ? 1 : 0)
                }
            }
        }
        .frame(height: trackHeight)
        .accessibilityHidden(true)
    }

    private func trackCell(amount: Double, brightness: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 0.7, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(LEDPhosphor.off)
            if amount >= 1 {
                shape.fill(LEDPhosphor.on.opacity(brightness))
            } else if amount > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(LEDPhosphor.on.opacity(brightness))
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
                scaleWindowSeconds = dispatch.zooms ? dispatch.windowSeconds : quietWindow
                showsScheduledClock = true
                showsPredictedMark = snapshot.hasPrediction
                showsDispatchChip = dispatch.zooms
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
        guard dispatch.zooms else { return }
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

private struct OccupancyDispatchChip: View {
    var row: TimetableOccupancyRow
    var end: Date
    var now: Date

    var body: some View {
        HStack(spacing: 5) {
            Text(row.clock)
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(
                timerInterval: countdown,
                countsDown: true,
                showsHours: false
            )
            .font(.caption2.weight(.semibold).monospacedDigit())
            .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spokenLine)
    }

    private var countdown: ClosedRange<Date> {
        if end >= now { return now...end }
        return now...now
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
