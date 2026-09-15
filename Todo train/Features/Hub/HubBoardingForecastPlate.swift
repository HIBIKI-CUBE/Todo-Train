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
    @Query(sort: \TimetableBlock.startsAt) private var blocks: [TimetableBlock]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @Environment(ArrivalForecastTraceLog.self) private var forecastLog
    @Environment(ArrivalForecastStore.self) private var forecastStore

    @State private var fillProgress: CGFloat = 0
    @State private var caretFraction: CGFloat = 0
    @State private var showsScheduledClock = false
    @State private var showsPredictedMark = false
    @State private var refinedMinutes: Int?
    @State private var inspectTrace: ArrivalForecastTrace?
    @State private var clockAnchor = Date()
    @State private var refineTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: clockAnchor, by: 60)) { timeline in
            let snapshot = displaySnapshot(at: timeline.date)
            plate(snapshot, at: timeline.date)
        }
        .frame(width: ticketWidth, height: plateHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.55) {
            guard settings.developerToolsUnlocked else { return }
            inspectTrace = forecastLog.latest(matchingTitle: ticket.title) ?? forecastLog.traces.first
        }
        .allowsHitTesting(settings.developerToolsUnlocked)
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

    private var showsDurationFoot: Bool {
        plateHeight >= 88
    }

    private func diaMarkMinutes(at now: Date) -> Int? {
        let next = blocks.filter { $0.isActive && $0.endsAt > now }.sorted { $0.startsAt < $1.startsAt }.first
        guard let next else { return nil }
        return TimetableFit.markMinutes(until: next.startsAt, now: now)
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

    private func plate(_ snapshot: BoardingForecast.Snapshot, at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            clocks(snapshot)
            track(snapshot, at: now)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background { StationSignHousing(rimLit: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(snapshot, at: now))
    }

    @ViewBuilder
    private func clocks(_ snapshot: BoardingForecast.Snapshot) -> some View {
        if snapshot.hasPrediction,
           let predicted = snapshot.predictedArrival,
           let predictedMinutes = snapshot.predictedMinutes {
            HStack(alignment: .top, spacing: 12) {
                clockColumn(
                    headline: BoardingForecast.scheduledHeadline,
                    time: BoardingForecast.timeString(from: snapshot.scheduledArrival),
                    foot: BoardingForecast.durationLabel(minutes: snapshot.scheduledMinutes),
                    visible: showsScheduledClock
                )
                clockColumn(
                    headline: BoardingForecast.predictedHeadline,
                    time: BoardingForecast.predictedTimeString(from: predicted),
                    foot: BoardingForecast.predictedCaption(
                        minutes: predictedMinutes,
                        sampleCount: snapshot.sampleCount
                    ),
                    visible: showsPredictedMark
                )
            }
        } else {
            clockColumn(
                headline: BoardingForecast.scheduledHeadline,
                time: BoardingForecast.timeString(from: snapshot.scheduledArrival),
                foot: showsDurationFoot
                    ? BoardingForecast.durationLabel(minutes: snapshot.scheduledMinutes)
                    : nil,
                visible: showsScheduledClock
            )
            .frame(maxWidth: .infinity)
        }
    }

    private func clockColumn(headline: String, time: String, foot: String?, visible: Bool) -> some View {
        VStack(alignment: .center, spacing: 1) {
            Text(headline)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(LEDPhosphor.on.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(time)
                .font(.system(size: timePointSize, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(LEDPhosphor.on)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if showsDurationFoot, let foot {
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

    private func track(_ snapshot: BoardingForecast.Snapshot, at now: Date) -> some View {
        let revealedMinutes = Double(snapshot.scheduledScaleMinutes) * fillProgress
        let fill = TicketDurationScale.filled(exactMinutes: revealedMinutes)
        let fillBrightness = fillBrightness(snapshot)
        let caretBrightness = caretBrightness(snapshot)
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

            if snapshot.hasPrediction {
                GeometryReader { geo in
                    let x = geo.size.width * caretFraction
                    TimetableCaret()
                        .fill(LEDPhosphor.on.opacity(caretBrightness))
                        .frame(width: 9, height: 7)
                        .position(x: x, y: 4)
                        .opacity(showsPredictedMark ? 1 : 0)
                }
            }

            if let mark = diaMarkMinutes(at: now) {
                GeometryReader { geo in
                    let x = geo.size.width * CGFloat(TicketDurationScale.unitFraction(minutes: mark))
                    Rectangle()
                        .fill(LEDPhosphor.on)
                        .frame(width: 2, height: 14)
                        .position(x: x, y: 12)
                }
            }
        }
        .frame(height: 17)
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

    private func accessibilityLabel(_ snapshot: BoardingForecast.Snapshot, at now: Date) -> String {
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
        if let mark = diaMarkMinutes(at: now) {
            parts.append("次のダイヤ \(mark)分先")
        }
        return parts.joined(separator: "。")
    }

    private func syncReveal(_ play: Bool) {
        let snapshot = displaySnapshot(at: .now)
        let scheduledFraction = CGFloat(
            TicketDurationScale.unitFraction(minutes: snapshot.scheduledScaleMinutes)
        )
        let predictedFraction = snapshot.predictedScaleMinutes.map {
            CGFloat(TicketDurationScale.unitFraction(minutes: $0))
        }

        if !play {
            var parked = Transaction()
            parked.animation = nil
            withTransaction(parked) {
                fillProgress = 0
                caretFraction = scheduledFraction
                showsScheduledClock = false
                showsPredictedMark = false
            }
            return
        }

        if reduceMotion {
            var parked = Transaction()
            parked.animation = nil
            withTransaction(parked) {
                fillProgress = 1
                caretFraction = predictedFraction ?? scheduledFraction
                showsScheduledClock = true
                showsPredictedMark = snapshot.hasPrediction
            }
            return
        }

        let motion = MarsTicketSpec.HubStack.TimetableReveal.self
        var parked = Transaction()
        parked.animation = nil
        withTransaction(parked) {
            fillProgress = 0
            caretFraction = scheduledFraction
            showsScheduledClock = false
            showsPredictedMark = false
        }
        withAnimation(.easeOut(duration: motion.fillDuration)) {
            fillProgress = 1
            showsScheduledClock = true
        }
        guard snapshot.hasPrediction, let predictedFraction else { return }
        withAnimation(
            .easeOut(duration: motion.caretAppearDuration).delay(motion.caretAppearDelay)
        ) {
            showsPredictedMark = true
        }
        withAnimation(
            .smooth(duration: motion.caretTravelDuration).delay(motion.caretTravelDelay)
        ) {
            caretFraction = predictedFraction
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
        let fraction = CGFloat(TicketDurationScale.unitFraction(minutes: minutes))
        if reduceMotion {
            caretFraction = fraction
        } else {
            withAnimation(.smooth(duration: 0.35)) {
                caretFraction = fraction
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

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let ticket = Ticket(title: "レビュー", estimatedSeconds: 30 * 60)
    container.mainContext.insert(ticket)
    return ZStack {
        Color(uiColor: .systemGroupedBackground)
        HubBoardingForecastPlate(ticket: ticket, ticketWidth: 320, plateHeight: 101)
    }
    .environment(AppSettings.shared)
    .environment(ArrivalForecastTraceLog.shared)
    .environment(ArrivalForecastStore.shared)
    .modelContainer(container)
}
