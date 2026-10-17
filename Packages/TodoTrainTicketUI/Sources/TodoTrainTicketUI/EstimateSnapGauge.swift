//
//  EstimateSnapGauge.swift
//  Todo train
//
//  Full-width linear snap gauge — sticky detents, spring escape (“ビュン”), Liquid Glass knob.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

public struct EstimateSnapGauge: View {
    @Binding var minutes: Int
    public var highlightedMinutes: Int?
    public var stopMinutes: [Int]
    public var maxMinutes: Int
    /// 左端の未選択から始める（残り時間の見積もり直し）。
    public var startsAtLeftUnselected: Bool
    /// 残り時間の見積もり直し用。分単位の帯（ゲージ上に淡く描く）。
    public var bandRangeMinutes: ClosedRange<Int>?
    public var minimumCommitTranslation: CGFloat
    public var requiresDragToCommit: Bool
    public var accessibilityLabelText: String
    /// When true, finger-up issues a ticket — quiet detent so sheet owns celebration.
    public var willIssue: () -> Bool = { false }
    public var onCommit: (() -> Void)?
    public var onLongPress: (() -> Void)?

    public init(
        minutes: Binding<Int>,
        highlightedMinutes: Int? = nil,
        stopMinutes: [Int] = EstimateSnapMapping.stops,
        maxMinutes: Int = EstimateSnapMapping.maxMinutes,
        startsAtLeftUnselected: Bool = false,
        bandRangeMinutes: ClosedRange<Int>? = nil,
        minimumCommitTranslation: CGFloat = 10,
        requiresDragToCommit: Bool = false,
        accessibilityLabelText: String = "見積もり",
        willIssue: @escaping () -> Bool = { false },
        onCommit: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil
    ) {
        _minutes = minutes
        self.highlightedMinutes = highlightedMinutes
        self.stopMinutes = stopMinutes
        self.maxMinutes = maxMinutes
        self.startsAtLeftUnselected = startsAtLeftUnselected
        self.bandRangeMinutes = bandRangeMinutes
        self.minimumCommitTranslation = minimumCommitTranslation
        self.requiresDragToCommit = requiresDragToCommit
        self.accessibilityLabelText = accessibilityLabelText
        self.willIssue = willIssue
        self.onCommit = onCommit
        self.onLongPress = onLongPress
    }

    @State private var displayFraction: CGFloat = 0
    @State private var anchoredMinutes: Int = 0
    @State private var isDragging = false
    @State private var selectionPulse = 0
    @State private var impactPulse = 0
    @State private var confirmPulse = 0
    @State private var dragStartAnchoredMinutes = 0
    @State private var suppressCommit = false

    private let trackHeight: CGFloat = 48
    private let knobSize: CGFloat = 32

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = displayFraction * width
            let fillWidth = max(min(max(displayFraction, 0), 1) * width, trackHeight / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .frame(height: trackHeight)
                    .ticketGlass(nil, in: Capsule())

                Capsule()
                    .fill(TicketGaugeInk.rail.opacity(0.28))
                    .frame(width: fillWidth, height: trackHeight)
                    .allowsHitTesting(false)

                if let bandRangeMinutes {
                    let lowX = EstimateSnapMapping.fraction(minutes: bandRangeMinutes.lowerBound, maxMinutes: maxMinutes) * width
                    let highX = EstimateSnapMapping.fraction(minutes: bandRangeMinutes.upperBound, maxMinutes: maxMinutes) * width
                    Capsule()
                        .fill(TicketGaugeInk.rail.opacity(0.14))
                        .frame(width: max(highX - lowX, 4), height: trackHeight)
                        .offset(x: lowX)
                        .allowsHitTesting(false)
                }

                ForEach(stopMinutes, id: \.self) { stop in
                    let x = EstimateSnapMapping.fraction(minutes: stop, maxMinutes: maxMinutes) * width
                    let isActive = anchoredMinutes == stop
                    let isHighlighted = highlightedMinutes == stop
                    Circle()
                        .fill(
                            isActive
                                ? TicketGaugeInk.rail
                                : (isHighlighted ? TicketGaugeInk.highlight : Color.primary.opacity(0.2))
                        )
                        .frame(width: isActive ? 7 : (isHighlighted ? 6 : 4),
                               height: isActive ? 7 : (isHighlighted ? 6 : 4))
                        .position(x: x, y: trackHeight / 2)
                        .allowsHitTesting(false)
                }

                Circle()
                    .fill(.clear)
                    .frame(width: knobSize, height: knobSize)
                    .ticketGlass(TicketGaugeInk.rail, in: Circle())
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
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue("\(minutes)分")
        .accessibilityAdjustableAction { direction in
            let stops = stopMinutes
            guard let index = stops.firstIndex(of: anchoredMinutes)
                    ?? stops.firstIndex(of: EstimateSnapMapping.snap(
                        rawMinutes: Double(minutes),
                        stops: stops
                    ))
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
        .sensoryFeedback(.impact(weight: .light, intensity: 1.0), trigger: confirmPulse)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if suppressCommit { return }
                if !isDragging {
                    isDragging = true
                    anchoredMinutes = resolvedAnchor(minutes)
                    dragStartAnchoredMinutes = startsAtLeftUnselected && minutes <= 0 ? 0 : anchoredMinutes
                }
                let issuingContext = willIssue()
                let finger = EstimateSnapMapping.unboundedFraction(
                    x: value.location.x,
                    width: width
                )
                let scrub = EstimateSnapMapping.stickyScrub(
                    fingerFraction: finger,
                    anchoredMinutes: anchoredMinutes,
                    stops: stopMinutes,
                    maxMinutes: maxMinutes
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
                    withAnimation(TicketGaugeInk.snap) {
                        displayFraction = EstimateSnapMapping.fraction(
                            minutes: anchoredMinutes,
                            maxMinutes: maxMinutes
                        )
                        isDragging = false
                    }
                    return
                }

                let issuing = willIssue()
                let translation = hypot(value.translation.width, value.translation.height)
                let primarilyVertical = EstimateSnapMapping.isPrimarilyVerticalDrag(
                    dx: value.translation.width,
                    dy: value.translation.height
                )

                if !EstimateSnapMapping.shouldCommitScrub(
                    requiresDragToCommit: requiresDragToCommit,
                    translation: translation,
                    minimumTranslation: minimumCommitTranslation,
                    isPrimarilyVertical: primarilyVertical,
                    startAnchoredMinutes: dragStartAnchoredMinutes,
                    endAnchoredMinutes: anchoredMinutes,
                    startsAtLeftUnselected: startsAtLeftUnselected
                ) {
                    withAnimation(TicketGaugeInk.soft) {
                        syncToMinutes(minutes, animated: false)
                    }
                    isDragging = false
                    return
                }

                if translation < 10 {
                    let tapped = EstimateSnapMapping.snap(
                        fraction: EstimateSnapMapping.fraction(x: value.location.x, width: width),
                        stops: stopMinutes,
                        maxMinutes: maxMinutes
                    )
                    if tapped != anchoredMinutes {
                        applyEscape(
                            to: tapped,
                            playHaptic: !issuing,
                            animated: !issuing
                        )
                    }
                }

                minutes = anchoredMinutes
                if requiresDragToCommit {
                    playConfirmHaptic()
                }
                let landed = EstimateSnapMapping.fraction(minutes: anchoredMinutes, maxMinutes: maxMinutes)

                if issuing {
                    displayFraction = landed
                    isDragging = false
                    onCommit?()
                } else {
                    withAnimation(TicketGaugeInk.snap) {
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
        let target = EstimateSnapMapping.fraction(minutes: stop, maxMinutes: maxMinutes)
        if animated {
            withAnimation(TicketGaugeInk.snap) {
                displayFraction = target
            }
        } else {
            withAnimation(TicketGaugeInk.soft) {
                displayFraction = target
            }
        }
    }

    private func syncToMinutes(_ value: Int, animated: Bool) {
        if startsAtLeftUnselected, value <= 0 {
            anchoredMinutes = 0
            displayFraction = 0
            return
        }
        let stop = resolvedAnchor(value)
        anchoredMinutes = stop
        let target = EstimateSnapMapping.fraction(minutes: stop, maxMinutes: maxMinutes)
        if animated {
            withAnimation(TicketGaugeInk.snap) {
                displayFraction = target
            }
        } else {
            displayFraction = target
        }
    }

    private func resolvedAnchor(_ value: Int) -> Int {
        if stopMinutes.contains(value) { return value }
        return EstimateSnapMapping.snap(rawMinutes: Double(value), stops: stopMinutes)
    }

    private func playConfirmHaptic() {
        confirmPulse += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            confirmPulse += 1
        }
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
