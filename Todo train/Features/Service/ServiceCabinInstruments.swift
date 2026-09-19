//
//  ServiceCabinInstruments.swift
//  Todo train
//
//  Focus strips + glass-cockpit BIT. Clock is live digits from the first light.
//  Lamps, tape, and occupancy move together with ため.
//

import SwiftUI

struct ServiceCabinInstruments: View {
    var lamp: ServiceCabinLamp
    var occupancyRows: [TimetableOccupancyRow]
    var occupancyMarks: [TimetableOccupancyMark]
    var dayText: String
    var now: Date
    var statusText: String = "運行中"
    var paused: Bool = false
    var occupancyActionTitle: String? = nil
    var occupancyAction: (() -> Void)? = nil
    var additionalOccupancyRows: [TimetableOccupancyRow] = []
    var additionalActionTitle: String? = nil
    var additionalAction: ((UUID) -> Void)? = nil
    var consistItems: [ServiceCabinConsistItem] = []
    var facts: [ServiceCabinDayFact] = []
    var clockHeight: CGFloat? = nil
    var expandsClock: Bool = false
    var pinsLower: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedRowCount = 0
    @State private var revealedConsistCount = 0
    @State private var testCount = 0
    @State private var settledCount = 0
    @State private var clockArmed = false

    private var hasOccupancy: Bool {
        !occupancyRows.isEmpty || !occupancyMarks.isEmpty || !additionalOccupancyRows.isEmpty
    }

    private var usesHeroClock: Bool {
        clockHeight != nil || expandsClock
    }

    private var displayedOccupancyRows: [TimetableOccupancyRow] {
        occupancyRows + additionalOccupancyRows
    }

    var body: some View {
        VStack(spacing: 0) {
            if lamp >= .test {
                chrome
                if pinsLower {
                    ScrollView {
                        lower
                    }
                    .scrollIndicators(.hidden)
                } else {
                    lower
                }
            }
        }
        .animation(nil, value: lamp)
        .sensoryFeedback(.selection, trigger: testCount)
        .sensoryFeedback(.selection, trigger: settledCount)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.88), trigger: clockArmed)
        .task(id: lamp) {
            await applyLampMotion()
        }
        .onAppear {
            if lamp >= .live {
                testCount = ServiceCabinAnnunciator.allCases.count
                clockArmed = true
                settledCount = ServiceCabinAnnunciator.allCases.count
                revealedRowCount = displayedOccupancyRows.count
                revealedConsistCount = consistItems.count
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            header
            FocusControlDivider()
            ServiceCabinAnnunciators(
                lamp: lamp,
                serviceOn: lamp >= .live,
                hasOccupancy: hasOccupancy,
                paused: paused,
                testCount: testCount,
                settledCount: settledCount
            )
            FocusControlDivider()
            if usesHeroClock {
                heroClock
                FocusControlDivider()
            }
        }
    }

    @ViewBuilder
    private var lower: some View {
        occupancy
        if !consistItems.isEmpty, lamp >= .live {
            FocusControlDivider()
            consist
        }
        if !facts.isEmpty, lamp >= .live {
            FocusControlDivider()
            factsStrip
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: TrainTheme.Space.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayText)
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundStyle(clockArmed ? FocusPanel.ink : FocusPanel.ink.opacity(0.22))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !usesHeroClock {
                        clockRow(fontSize: 22)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusText)
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(clockArmed ? FocusPanel.ink : FocusPanel.ink.opacity(0.22))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.trailing)
            }
            if !usesHeroClock {
                ServiceCabinSecondsRail(lamp: lamp, armed: clockArmed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(FocusPanel.fill)
        .animation(reduceMotion ? nil : ServiceCabinMotion.clockLock, value: clockArmed)
        .accessibilityAddTraits(.isHeader)
    }

    private var heroClock: some View {
        GeometryReader { geo in
            let fontSize = heroClockFontSize(in: geo.size)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                clockRow(fontSize: fontSize, secondsRelative: 0.58)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(clockArmed ? 1 : 0.965)
                    .animation(reduceMotion ? nil : ServiceCabinMotion.clockLock, value: clockArmed)
                Spacer(minLength: 0)
                ServiceCabinSecondsRail(lamp: lamp, armed: clockArmed)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: expandsClock ? nil : clockHeight)
        .frame(maxHeight: expandsClock ? .infinity : nil)
        .background(Color.black)
        .overlay {
            Rectangle()
                .strokeBorder(FocusPanel.hairline, lineWidth: FocusPanel.hairlineWidth)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    private func clockRow(fontSize: CGFloat, secondsRelative: CGFloat = 1) -> some View {
        let parts = ServiceCabinSequence.clockDigits(at: now)
        let colonOn = !clockArmed || reduceMotion || Int(now.timeIntervalSinceReferenceDate) % 2 == 0
        let secondSize = fontSize * secondsRelative
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.hourMinute)
            Text(":")
                .font(.system(size: secondSize, weight: .medium, design: .default))
                .opacity(colonOn ? 1 : 0.22)
            Text(parts.second)
                .font(.system(size: secondSize, weight: .medium, design: .default))
                .contentTransition(reduceMotion || !clockArmed ? .identity : .numericText())
        }
        .font(.system(size: fontSize, weight: fontSize >= 40 ? .semibold : .medium, design: .default))
        .monospacedDigit()
        .foregroundStyle(clockArmed ? FocusPanel.ink : FocusPanel.ink.opacity(0.18))
        .minimumScaleFactor(0.4)
        .lineLimit(1)
        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: parts.second)
        .animation(reduceMotion ? nil : ServiceCabinMotion.clockLock, value: clockArmed)
        .accessibilityLabel("時刻")
        .accessibilityValue("\(parts.hourMinute):\(parts.second)")
    }

    private func heroClockFontSize(in size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.36
        let byHeight = size.height * 0.52
        return min(byWidth, byHeight, 80)
    }

    @ViewBuilder
    private var occupancy: some View {
        VStack(alignment: .leading, spacing: 8) {
            ServiceCabinTape(
                lamp: lamp,
                rest: ServiceCabinSequence.tapeRest(marks: occupancyMarks),
                reduceMotion: reduceMotion
            )

            if lamp >= .live, !displayedOccupancyRows.isEmpty {
                ForEach(Array(displayedOccupancyRows.enumerated()), id: \.element.id) { index, row in
                    OccupancyDestinationSign(
                        row: row,
                        surface: .cabin,
                        compact: false,
                        actionTitle: occupancyActionTitle(for: row),
                        action: occupancyAction(for: row)
                    )
                    .opacity(index < revealedRowCount ? 1 : 0)
                    .offset(y: index < revealedRowCount ? 0 : 10)
                    .animation(
                        reduceMotion ? nil : ServiceCabinMotion.rowIn,
                        value: revealedRowCount
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusPanel.fill)
        .allowsHitTesting(lamp >= .live)
    }

    @ViewBuilder
    private var consist: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(consistItems.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .medium, design: .default))
                        .foregroundStyle(FocusPanel.ink.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(item.minutes)分")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(FocusPanel.muted)
                }
                .opacity(index < revealedConsistCount ? 1 : 0)
                .offset(y: index < revealedConsistCount ? 0 : 8)
                .animation(
                    reduceMotion ? nil : ServiceCabinMotion.rowIn,
                    value: revealedConsistCount
                )
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusPanel.fill)
        .allowsHitTesting(false)
        .accessibilityLabel("編成")
    }

    private var factsStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.label)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(FocusPanel.muted)
                    Text(fact.value)
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(FocusPanel.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FocusPanel.fill)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日の記録")
    }

    private func occupancyActionTitle(for row: TimetableOccupancyRow) -> String? {
        if row.id == occupancyRows.first?.id {
            return occupancyActionTitle
        }
        if additionalOccupancyRows.contains(where: { $0.id == row.id }) {
            return additionalActionTitle
        }
        return nil
    }

    private func occupancyAction(for row: TimetableOccupancyRow) -> (() -> Void)? {
        if row.id == occupancyRows.first?.id {
            return occupancyAction
        }
        if additionalOccupancyRows.contains(where: { $0.id == row.id }) {
            return { additionalAction?(row.id) }
        }
        return nil
    }

    private func applyLampMotion() async {
        if reduceMotion {
            clockArmed = lamp >= .live
            testCount = lamp >= .test ? ServiceCabinAnnunciator.allCases.count : 0
            settledCount = lamp >= .live ? ServiceCabinAnnunciator.allCases.count : 0
            revealedRowCount = displayedOccupancyRows.count
            revealedConsistCount = consistItems.count
            return
        }

        switch lamp {
        case .dark:
            clockArmed = false
            testCount = 0
            settledCount = 0
            revealedRowCount = 0
            revealedConsistCount = 0
        case .test:
            clockArmed = false
            revealedRowCount = 0
            revealedConsistCount = 0
            if settledCount > 0 {
                testCount = ServiceCabinAnnunciator.allCases.count
                settledCount = 0
                return
            }
            testCount = 0
            settledCount = 0
            for count in 1...ServiceCabinAnnunciator.allCases.count {
                testCount = count
                try? await Task.sleep(for: .seconds(ServiceCabinSequence.lampTestStaggerSeconds))
                if Task.isCancelled { return }
            }
        case .live, .ready:
            testCount = ServiceCabinAnnunciator.allCases.count
            async let rows = revealOccupancyRows()
            async let clock = armClock()
            async let consist = delayedConsist()
            await settleLamps()
            await rows
            await clock
            await consist
        }
    }

    private func armClock() async {
        if clockArmed { return }
        try? await Task.sleep(for: .seconds(ServiceCabinSequence.clockArmDelaySeconds))
        if Task.isCancelled { return }
        clockArmed = true
    }

    private func settleLamps() async {
        if settledCount >= ServiceCabinAnnunciator.allCases.count { return }
        try? await Task.sleep(for: .seconds(ServiceCabinSequence.lampSettleHoldSeconds))
        if Task.isCancelled { return }
        for count in 1...ServiceCabinAnnunciator.allCases.count {
            settledCount = count
            try? await Task.sleep(for: .seconds(ServiceCabinSequence.lampSettleStaggerSeconds))
            if Task.isCancelled { return }
        }
    }

    private func delayedConsist() async {
        try? await Task.sleep(for: .milliseconds(420))
        if Task.isCancelled { return }
        await revealConsist()
    }

    private func revealOccupancyRows() async {
        if lamp < .live {
            revealedRowCount = 0
            return
        }
        if reduceMotion || displayedOccupancyRows.isEmpty {
            revealedRowCount = displayedOccupancyRows.count
            return
        }
        if revealedRowCount >= displayedOccupancyRows.count { return }
        revealedRowCount = 0
        for count in 1...displayedOccupancyRows.count {
            try? await Task.sleep(for: .milliseconds(170))
            if Task.isCancelled { return }
            revealedRowCount = count
        }
    }

    private func revealConsist() async {
        if lamp < .live || consistItems.isEmpty {
            revealedConsistCount = consistItems.isEmpty ? 0 : consistItems.count
            return
        }
        if reduceMotion {
            revealedConsistCount = consistItems.count
            return
        }
        if revealedConsistCount >= consistItems.count { return }
        revealedConsistCount = 0
        for count in 1...consistItems.count {
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            revealedConsistCount = count
        }
    }

    private var accessibilityLabel: String {
        switch lamp {
        case .dark:
            return "盤はまだ暗い"
        case .test:
            return "表示灯試験"
        case .live:
            return statusText
        case .ready:
            return "切符へ"
        }
    }
}
