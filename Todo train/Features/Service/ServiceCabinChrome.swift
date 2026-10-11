//
//  ServiceCabinChrome.swift
//  Todo train
//
//  Focus の盤の上に、実機の初期化だけ借りる。
//  表示灯は順に点いてため、テープと秒尺は別々に振り切る。時計は実時刻のまま灯る。
//  光の後付けはしない。
//

import SwiftUI

enum ServiceCabinMotion {
    static let tapeOut = Animation.easeIn(duration: ServiceCabinSequence.sweepOutSeconds)
    static let tapeSettle = Animation.spring(response: 0.56, dampingFraction: 0.76)
    static let secondsOut = Animation.easeIn(duration: ServiceCabinSequence.secondsSweepOutSeconds)
    static let secondsSettle = Animation.easeOut(duration: 0.42)
    static let clockLock = Animation.spring(response: 0.48, dampingFraction: 0.78)
    static let lampClick = Animation.easeOut(duration: 0.09)
    static let rowIn = Animation.spring(response: 0.44, dampingFraction: 0.86)
    /// Shutdown overview: compressed civil day pushes into the service window.
    static let overviewPush = Animation.spring(response: 0.82, dampingFraction: 0.86)
}

struct ServiceCabinPanel<Content: View>: View {
    var powered: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FocusPanel.fill)
            .opacity(powered ? 1 : 0)
            .animation(.easeOut(duration: 0.42), value: powered)
            .accessibilityHidden(!powered)
    }
}

/// Small state lamps. The word is the reading; the box lights when that reading is hot.
struct ServiceCabinAnnunciators: View {
    var lamp: ServiceCabinLamp
    var serviceOn: Bool
    var hasOccupancy: Bool
    var track: ServiceCabinTrackReading
    var paused: Bool
    var testCount: Int = ServiceCabinAnnunciator.allCases.count
    var settledCount: Int = ServiceCabinAnnunciator.allCases.count

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(ServiceCabinAnnunciator.allCases.enumerated()), id: \.element) { _, id in
                cell(id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("表示灯")
    }

    private func cell(_ id: ServiceCabinAnnunciator) -> some View {
        let on = ServiceCabinSequence.annunciatorLit(
            id,
            lamp: lamp,
            serviceOn: serviceOn,
            hasOccupancy: hasOccupancy,
            paused: paused,
            testCount: testCount,
            settledCount: settledCount
        )
        let legend = ServiceCabinSequence.annunciatorLegend(
            id,
            showsLiveReading: lamp >= .live && isSettled(id),
            serviceOn: serviceOn,
            track: track,
            paused: paused
        )
        return Text(legend)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundStyle(on ? FocusPanel.ink : FocusPanel.muted)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(on ? FocusPanel.fillRaised : Color.white.opacity(0.03))
            .overlay {
                Rectangle()
                    .strokeBorder(
                        on ? Color.white.opacity(0.55) : FocusPanel.hairline,
                        lineWidth: FocusPanel.hairlineWidth
                    )
            }
            .animation(ServiceCabinMotion.lampClick, value: on)
            .animation(ServiceCabinMotion.lampClick, value: legend)
            .accessibilityLabel(legend)
            .accessibilityValue(lamp == .test || (lamp >= .live && !isSettled(id)) ? "試験" : (on ? "点灯" : "消灯"))
    }

    private func isSettled(_ id: ServiceCabinAnnunciator) -> Bool {
        let index = ServiceCabinAnnunciator.allCases.firstIndex(of: id) ?? 0
        return settledCount > index
    }
}

/// Cluster BIT: needle out, hold at the stop, then rest on the live value.
struct ServiceCabinTape: View {
    var lamp: ServiceCabinLamp
    var rest: CGFloat
    var reduceMotion: Bool

    @State private var needle: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let inner = max(geo.size.width - 4, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: max(6, inner * needle), height: 8)
                    .offset(x: 2)
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: 12)
                    .offset(x: 2 + inner * needle)
            }
        }
        .frame(height: 12)
        .clipped()
        .accessibilityHidden(true)
        .task(id: lamp) {
            await sweep()
        }
        .onChange(of: rest) { _, _ in
            guard lamp >= .live else { return }
            needle = rest
        }
    }

    private func sweep() async {
        if reduceMotion || lamp == .dark {
            needle = lamp >= .live ? rest : 0
            return
        }
        if lamp == .test {
            needle = 0
            withAnimation(ServiceCabinMotion.tapeOut) {
                needle = 1
            }
            return
        }
        if lamp >= .live {
            try? await Task.sleep(for: .seconds(ServiceCabinSequence.tapeSettleDelaySeconds))
            if Task.isCancelled { return }
            withAnimation(ServiceCabinMotion.tapeSettle) {
                needle = rest
            }
        }
    }
}

/// Clock's own tape: slower sweep than occupancy, then lock onto this minute.
struct ServiceCabinSecondsRail: View {
    var lamp: ServiceCabinLamp
    var armed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var needle: CGFloat = 0
    @State private var tracking = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion || !tracking ? 1 : 0.05)) { context in
            let fraction = tracking
                ? ServiceCabinSequence.secondsRailRest(at: context.date)
                : needle
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(FocusPanel.hairline)
                    Rectangle()
                        .fill(FocusPanel.ink.opacity(railInk))
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 2)
        }
        .accessibilityHidden(true)
        .task(id: lamp) {
            await onLamp()
        }
        .task(id: armed) {
            await onArmed()
        }
    }

    private var railInk: Double {
        if armed { return 0.7 }
        if lamp == .test { return 0.38 }
        return 0.2
    }

    private func onLamp() async {
        if reduceMotion {
            tracking = armed
            needle = armed ? ServiceCabinSequence.secondsRailRest(at: .now) : 0
            return
        }
        if lamp == .dark {
            tracking = false
            needle = 0
            return
        }
        if lamp == .test {
            tracking = false
            needle = 0
            withAnimation(ServiceCabinMotion.secondsOut) {
                needle = 1
            }
            return
        }
        if !armed {
            tracking = false
            needle = 1
        }
    }

    private func onArmed() async {
        if reduceMotion {
            tracking = armed
            return
        }
        guard armed else {
            tracking = false
            return
        }
        let live = ServiceCabinSequence.secondsRailRest(at: .now)
        withAnimation(ServiceCabinMotion.secondsSettle) {
            needle = live
        }
        try? await Task.sleep(for: .seconds(0.42))
        if Task.isCancelled { return }
        tracking = true
    }
}
