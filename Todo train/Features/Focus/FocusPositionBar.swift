//
//  FocusPositionBar.swift
//  Todo train
//

import SwiftUI
import TodoTrainTicketUI

/// 現在位置の割合。運転台の `FocusProgressBar` と同じ平らな意匠。
struct FocusPositionBar: View {
    @Binding var progressPercent: Int
    var onCommit: () -> Void

    private let stopPercents = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    private let maxPercent = 100
    private let touchHeight: CGFloat = 48
    private let trackHeight: CGFloat = 6

    @State private var displayFraction: CGFloat = 0
    @State private var anchoredPercent = 0
    @State private var isDragging = false
    @State private var dragStartAnchored = 0
    @State private var confirmPulse = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = displayFraction * width
            let fillWidth = max(min(displayFraction, 1), 0) * width
            let trackY = (touchHeight - trackHeight) / 2
            let fill = CockpitColors.amber

            ZStack(alignment: .leading) {
                Color.clear
                    .frame(height: touchHeight)
                    .contentShape(Rectangle())
                    .highPriorityGesture(scrubGesture(width: width))

                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: width, height: trackHeight)
                    .offset(y: trackY)
                    .allowsHitTesting(false)

                Capsule()
                    .fill(fill.opacity(progressPercent > 0 ? 0.95 : 0))
                    .frame(width: max(fillWidth, progressPercent > 0 ? 2 : 0), height: trackHeight)
                    .offset(y: trackY)
                    .allowsHitTesting(false)

                ForEach(stopPercents, id: \.self) { stop in
                    let x = CGFloat(stop) / CGFloat(maxPercent) * width
                    let isMajor = stop % 20 == 0 || stop == 100
                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.35 : 0.18))
                        .frame(width: 1, height: isMajor ? 10 : 6)
                        .position(x: x, y: touchHeight / 2)
                        .allowsHitTesting(false)
                }

                if progressPercent > 0 {
                    let headW: CGFloat = 12
                    let headH: CGFloat = 8
                    TrainHeadShape()
                        .fill(fill)
                        .frame(width: headW, height: headH)
                        .offset(
                            x: min(max(knobX - headW * 0.72, 0), max(width - headW, 0)),
                            y: (touchHeight - headH) / 2
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: touchHeight)
        .onAppear { syncToPercent(progressPercent, animated: false) }
        .onChange(of: progressPercent) { _, newValue in
            guard !isDragging else { return }
            syncToPercent(newValue, animated: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("現在位置")
        .accessibilityValue(accessibilityValue)
        .sensoryFeedback(.impact(weight: .light, intensity: 1.0), trigger: confirmPulse)
    }

    private var accessibilityValue: String {
        guard progressPercent > 0 else { return "未選択" }
        if progressPercent == 100 { return "10割" }
        return "\(progressPercent / 10)割"
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    anchoredPercent = resolvedAnchor(progressPercent)
                    dragStartAnchored = progressPercent <= 0 ? 0 : anchoredPercent
                }
                let finger = EstimateSnapMapping.unboundedFraction(x: value.location.x, width: width)
                let scrub: EstimateSnapMapping.StickyScrub
                if progressPercent <= 0, anchoredPercent <= 0 {
                    scrub = EstimateSnapMapping.scrubFromUnselected(
                        fingerFraction: finger,
                        stops: stopPercents,
                        maxMinutes: maxPercent
                    )
                } else {
                    scrub = EstimateSnapMapping.stickyScrub(
                        fingerFraction: finger,
                        anchoredMinutes: anchoredPercent,
                        stops: stopPercents,
                        maxMinutes: maxPercent
                    )
                }
                if scrub.didEscape {
                    applyEscape(to: scrub.anchoredMinutes)
                } else {
                    displayFraction = scrub.displayFraction
                }
            }
            .onEnded { value in
                let finger = EstimateSnapMapping.unboundedFraction(x: value.location.x, width: width)
                let translation = hypot(value.translation.width, value.translation.height)
                let primarilyVertical = EstimateSnapMapping.isPrimarilyVerticalDrag(
                    dx: value.translation.width,
                    dy: value.translation.height
                )
                if !EstimateSnapMapping.shouldCommitScrub(
                    requiresDragToCommit: true,
                    translation: translation,
                    minimumTranslation: 24,
                    isPrimarilyVertical: primarilyVertical,
                    startAnchoredMinutes: dragStartAnchored,
                    endAnchoredMinutes: anchoredPercent,
                    startsAtLeftUnselected: true
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        syncToPercent(progressPercent, animated: false)
                    }
                    isDragging = false
                    return
                }

                if translation < 10 {
                    let tapped = EstimateSnapMapping.snap(
                        fraction: EstimateSnapMapping.fraction(x: value.location.x, width: width),
                        stops: stopPercents,
                        maxMinutes: maxPercent
                    )
                    if tapped != anchoredPercent {
                        applyEscape(to: tapped)
                    }
                }

                progressPercent = anchoredPercent
                confirmPulse += 1
                isDragging = false
                onCommit()
            }
    }

    private func resolvedAnchor(_ percent: Int) -> Int {
        if percent <= 0 { return 0 }
        return EstimateSnapMapping.snap(rawMinutes: Double(percent), stops: stopPercents)
    }

    private func applyEscape(to percent: Int) {
        anchoredPercent = percent
        withAnimation(.easeOut(duration: 0.18)) {
            displayFraction = EstimateSnapMapping.fraction(minutes: percent, maxMinutes: maxPercent)
        }
    }

    private func syncToPercent(_ percent: Int, animated: Bool) {
        let anchor = resolvedAnchor(percent)
        anchoredPercent = anchor
        let target = EstimateSnapMapping.fraction(minutes: anchor, maxMinutes: maxPercent)
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { displayFraction = target }
        } else {
            displayFraction = target
        }
    }
}
