//
//  EstimateSnapGauge.swift
//  Todo train
//
//  Full-width linear snap gauge — sticky detents, spring escape (“ビュン”), Liquid Glass knob.
//

import SwiftUI

struct EstimateSnapGauge: View {
    @Binding var minutes: Int
    var highlightedMinutes: Int?
    /// When true, finger-up issues a ticket — quiet detent so sheet owns celebration.
    var willIssue: () -> Bool = { false }
    var onCommit: (() -> Void)?
    var onLongPress: (() -> Void)?

    @State private var displayFraction: CGFloat = 0.5
    @State private var anchoredMinutes: Int = 30
    @State private var isDragging = false
    @State private var selectionPulse = 0
    @State private var impactPulse = 0
    @State private var suppressCommit = false

    private let trackHeight: CGFloat = 48
    private let knobSize: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = displayFraction * width
            let fillWidth = max(min(max(displayFraction, 0), 1) * width, trackHeight / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .frame(height: trackHeight)
                    .glassEffect(.regular, in: .capsule)

                Capsule()
                    .fill(TrainTheme.rail.opacity(0.28))
                    .frame(width: fillWidth, height: trackHeight)
                    .allowsHitTesting(false)

                ForEach(EstimateSnapMapping.stops, id: \.self) { stop in
                    let x = EstimateSnapMapping.fraction(minutes: stop) * width
                    let isActive = anchoredMinutes == stop
                    let isHighlighted = highlightedMinutes == stop
                    Circle()
                        .fill(
                            isActive
                                ? TrainTheme.rail
                                : (isHighlighted ? TrainTheme.signalGreen : Color.primary.opacity(0.2))
                        )
                        .frame(width: isActive ? 7 : (isHighlighted ? 6 : 4),
                               height: isActive ? 7 : (isHighlighted ? 6 : 4))
                        .position(x: x, y: trackHeight / 2)
                        .allowsHitTesting(false)
                }

                Circle()
                    .fill(.clear)
                    .frame(width: knobSize, height: knobSize)
                    .glassEffect(
                        .regular.tint(TrainTheme.rail).interactive(),
                        in: .circle
                    )
                    .position(x: knobX, y: trackHeight / 2)
                    .allowsHitTesting(false)
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(scrubGesture(width: width))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55, maximumDistance: 8)
                    .onEnded { _ in
                        suppressCommit = true
                        onLongPress?()
                    }
            )
        }
        .frame(height: trackHeight)
        .onAppear {
            syncToMinutes(minutes, animated: false)
        }
        .onChange(of: minutes) { _, newValue in
            guard !isDragging else { return }
            syncToMinutes(newValue, animated: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("見積もり")
        .accessibilityValue("\(minutes)分")
        .accessibilityAdjustableAction { direction in
            let stops = EstimateSnapMapping.stops
            guard let index = stops.firstIndex(of: anchoredMinutes)
                    ?? stops.firstIndex(of: EstimateSnapMapping.snap(rawMinutes: Double(minutes)))
            else { return }
            let issuingContext = willIssue()
            switch direction {
            case .increment:
                if index + 1 < stops.count {
                    applyEscape(
                        to: stops[index + 1],
                        playHaptic: !issuingContext,
                        animated: !issuingContext
                    )
                    if !issuingContext { selectionPulse += 1 }
                }
            case .decrement:
                if index > 0 {
                    applyEscape(
                        to: stops[index - 1],
                        playHaptic: !issuingContext,
                        animated: !issuingContext
                    )
                    if !issuingContext { selectionPulse += 1 }
                }
            @unknown default:
                break
            }
        }
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: impactPulse)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if suppressCommit { return }
                if !isDragging {
                    isDragging = true
                    anchoredMinutes = resolvedAnchor(minutes)
                }
                let issuingContext = willIssue()
                let finger = EstimateSnapMapping.unboundedFraction(
                    x: value.location.x,
                    width: width
                )
                let scrub = EstimateSnapMapping.stickyScrub(
                    fingerFraction: finger,
                    anchoredMinutes: anchoredMinutes
                )
                if scrub.didEscape {
                    // Title ready → issue path owns celebration; quiet detent while scrubbing.
                    applyEscape(
                        to: scrub.anchoredMinutes,
                        playHaptic: !issuingContext,
                        animated: !issuingContext
                    )
                } else {
                    displayFraction = scrub.displayFraction
                }
            }
            .onEnded { value in
                defer { suppressCommit = false }
                let finger = EstimateSnapMapping.unboundedFraction(
                    x: value.location.x,
                    width: width
                )

                if suppressCommit {
                    withAnimation(TrainTheme.Motion.gaugeSnap) {
                        displayFraction = EstimateSnapMapping.fraction(minutes: anchoredMinutes)
                        isDragging = false
                    }
                    return
                }

                let issuing = willIssue()
                let translation = hypot(value.translation.width, value.translation.height)

                if translation < 10 {
                    let tapped = EstimateSnapMapping.stop(forFingerFraction: finger)
                    if tapped != anchoredMinutes {
                        applyEscape(
                            to: tapped,
                            playHaptic: !issuing,
                            animated: !issuing
                        )
                    }
                }

                minutes = anchoredMinutes
                let landed = EstimateSnapMapping.fraction(minutes: anchoredMinutes)

                if issuing {
                    displayFraction = landed
                    isDragging = false
                    onCommit?()
                } else {
                    withAnimation(TrainTheme.Motion.gaugeSnap) {
                        displayFraction = landed
                        isDragging = false
                    }
                    onCommit?()
                }
            }
    }

    private func applyEscape(to stop: Int, playHaptic: Bool, animated: Bool) {
        anchoredMinutes = stop
        minutes = stop
        if playHaptic {
            impactPulse += 1
        }
        let target = EstimateSnapMapping.fraction(minutes: stop)
        if animated {
            withAnimation(TrainTheme.Motion.gaugeSnap) {
                displayFraction = target
            }
        } else {
            withAnimation(TrainTheme.Motion.soft) {
                displayFraction = target
            }
        }
    }

    private func syncToMinutes(_ value: Int, animated: Bool) {
        let stop = resolvedAnchor(value)
        anchoredMinutes = stop
        let target = EstimateSnapMapping.fraction(minutes: stop)
        if animated {
            withAnimation(TrainTheme.Motion.gaugeSnap) {
                displayFraction = target
            }
        } else {
            displayFraction = target
        }
    }

    private func resolvedAnchor(_ value: Int) -> Int {
        if EstimateSnapMapping.stops.contains(value) { return value }
        return EstimateSnapMapping.snap(rawMinutes: Double(value))
    }
}

#Preview {
    StatefulPreview()
}

private struct StatefulPreview: View {
    @State private var minutes = 30

    var body: some View {
        VStack(spacing: 24) {
            Text("\(minutes)")
                .font(.system(size: 56, weight: .medium, design: .rounded))
                .monospacedDigit()
            EstimateSnapGauge(minutes: $minutes, highlightedMinutes: 30)
                .padding(.horizontal)
        }
        .padding()
    }
}
