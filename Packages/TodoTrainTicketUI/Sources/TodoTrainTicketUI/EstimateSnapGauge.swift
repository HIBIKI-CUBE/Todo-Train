//
//  EstimateSnapGauge.swift
//  Todo train
//
//  Full-width linear snap gauge — sticky detents, spring escape (“ビュン”), Liquid Glass knob.
//  `.ticket` は発券の見た目。`.cabin` は盤の色と振動だけを差し替える。
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

public enum EstimateSnapGaugeStyle: Sendable, Equatable {
    /// 発券画面。Liquid Glass、アクセントの塗り、緑の推し点。
    case ticket
    /// 運転台。純黒の溝、白のインク、平らなつまみ。
    case cabin
}

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
    public var style: EstimateSnapGaugeStyle
    /// `.cabin` のホーム帯を、答えが幅の中のときに明るくする。
    public var homeBandLit: Bool
    /// nil のときは「N分」。位置確認は割の読みを渡す。
    public var accessibilityValueText: String?
    /// When true, finger-up issues a ticket — quiet detent so sheet owns celebration.
    public var willIssue: () -> Bool = { false }
    public var onCommit: (() -> Void)?
    public var onLongPress: (() -> Void)?
    public var onTouchingChange: ((Bool) -> Void)?

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
        style: EstimateSnapGaugeStyle = .ticket,
        homeBandLit: Bool = false,
        accessibilityValueText: String? = nil,
        willIssue: @escaping () -> Bool = { false },
        onCommit: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onTouchingChange: ((Bool) -> Void)? = nil
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
        self.style = style
        self.homeBandLit = homeBandLit
        self.accessibilityValueText = accessibilityValueText
        self.willIssue = willIssue
        self.onCommit = onCommit
        self.onLongPress = onLongPress
        self.onTouchingChange = onTouchingChange
    }

    @State private var displayFraction: CGFloat = 0
    @State private var anchoredMinutes: Int = 0
    @State private var isDragging = false
    @State private var selectionPulse = 0
    @State private var impactPulse = 0
    @State private var confirmPulse = 0
    @State private var cabinSelectionPulse = 0
    @State private var overscrollPulse = 0
    @State private var wasOverscrolling = false
    @State private var dragStartAnchoredMinutes = 0
    @State private var suppressCommit = false

    private let trackHeight: CGFloat = 48
    private let knobSize: CGFloat = 32

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            chrome(width: width)
                .frame(height: trackHeight)
                .contentShape(Rectangle())
                .highPriorityGesture(scrubGesture(width: width))
                .modifier(EstimateSnapLongPress(enabled: onLongPress != nil) {
                    suppressCommit = true
                    onLongPress?()
                })
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
        .accessibilityValue(accessibilityValueText ?? "\(minutes)分")
        .accessibilityAdjustableAction { direction in
            let stops = stopMinutes
            if startsAtLeftUnselected, anchoredMinutes <= 0 {
                if direction == .increment, let first = stops.first {
                    let issuingContext = willIssue()
                    applyEscape(
                        to: first,
                        playHaptic: !issuingContext,
                        animated: !issuingContext
                    )
                    noteAdjustableDetent(issuing: issuingContext)
                }
                return
            }
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
                    noteAdjustableDetent(issuing: issuingContext)
                }
            case .decrement:
                if index > 0 {
                    applyEscape(
                        to: stops[index - 1],
                        playHaptic: !issuingContext,
                        animated: !issuingContext
                    )
                    noteAdjustableDetent(issuing: issuingContext)
                }
            @unknown default:
                break
            }
        }
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: impactPulse)
        .sensoryFeedback(.impact(weight: .light, intensity: 1.0), trigger: confirmPulse)
        .sensoryFeedback(.selection, trigger: cabinSelectionPulse)
        .sensoryFeedback(.impact(weight: .light, intensity: 1.0), trigger: overscrollPulse)
    }

    @ViewBuilder
    private func chrome(width: CGFloat) -> some View {
        switch style {
        case .ticket:
            ticketChrome(width: width)
        case .cabin:
            cabinChrome(width: width)
        }
    }

    private func ticketChrome(width: CGFloat) -> some View {
        let knobX = displayFraction * width
        let fillWidth = max(min(max(displayFraction, 0), 1) * width, trackHeight / 2)
        return ZStack(alignment: .leading) {
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
    }

    private func cabinChrome(width: CGFloat) -> some View {
        let knobX = cabinX(displayFraction, width: width)
        let clamped = min(max(displayFraction, 0), 1)
        let fillWidth = cabinX(clamped, width: width)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(CabinGaugeInk.groove)
                .frame(height: trackHeight)
                .overlay {
                    Capsule()
                        .strokeBorder(CabinGaugeInk.hairline, lineWidth: 1)
                }
                .overlay {
                    Capsule()
                        .stroke(Color.black.opacity(0.55), lineWidth: 2.5)
                        .blur(radius: 0.8)
                        .offset(y: 1)
                        .mask {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.black, .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                }

            if clamped > 0 {
                Capsule()
                    .fill(CabinGaugeInk.fill)
                    .frame(width: max(fillWidth, trackHeight / 2), height: trackHeight)
                    .allowsHitTesting(false)
            }

            if let bandRangeMinutes {
                let lowX = cabinX(
                    EstimateSnapMapping.fraction(minutes: bandRangeMinutes.lowerBound, maxMinutes: maxMinutes),
                    width: width
                )
                let highX = cabinX(
                    EstimateSnapMapping.fraction(minutes: bandRangeMinutes.upperBound, maxMinutes: maxMinutes),
                    width: width
                )
                Capsule()
                    .fill(homeBandLit ? CabinGaugeInk.bandLit : CabinGaugeInk.band)
                    .frame(width: max(highX - lowX, 4), height: trackHeight)
                    .offset(x: lowX)
                    .allowsHitTesting(false)
            }

            ForEach(stopMinutes, id: \.self) { stop in
                let x = cabinX(
                    EstimateSnapMapping.fraction(minutes: stop, maxMinutes: maxMinutes),
                    width: width
                )
                if anchoredMinutes != stop {
                    if highlightedMinutes == stop {
                        Circle()
                            .strokeBorder(CabinGaugeInk.ring, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                            .position(x: x, y: trackHeight / 2)
                            .allowsHitTesting(false)
                    } else {
                        Circle()
                            .fill(CabinGaugeInk.stop)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: trackHeight / 2)
                            .allowsHitTesting(false)
                    }
                }
            }

            Circle()
                .fill(CabinGaugeInk.knob)
                .overlay {
                    Circle().strokeBorder(CabinGaugeInk.knobEdge, lineWidth: 1)
                }
                .frame(width: knobSize, height: knobSize)
                .position(x: knobX, y: trackHeight / 2)
                .allowsHitTesting(false)
        }
    }

    /// つまみの半径ぶん内側に 0 と 1 を置き、その外はゴムの伸び。
    private func cabinX(_ fraction: CGFloat, width: CGFloat) -> CGFloat {
        let inset = knobSize / 2
        let travel = max(width - knobSize, 1)
        return inset + fraction * travel
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if suppressCommit { return }
                if !isDragging {
                    updateDragging(true)
                    anchoredMinutes = resolvedAnchor(minutes)
                    dragStartAnchoredMinutes = startsAtLeftUnselected && minutes <= 0 ? 0 : anchoredMinutes
                }
                let issuingContext = willIssue()
                let finger = EstimateSnapMapping.unboundedFraction(
                    x: value.location.x,
                    width: width
                )
                noteOverscroll(finger)
                let scrub: EstimateSnapMapping.StickyScrub
                if startsAtLeftUnselected, minutes <= 0, anchoredMinutes <= 0 {
                    scrub = EstimateSnapMapping.scrubFromUnselected(
                        fingerFraction: finger,
                        stops: stopMinutes,
                        maxMinutes: maxMinutes
                    )
                } else {
                    scrub = EstimateSnapMapping.stickyScrub(
                        fingerFraction: finger,
                        anchoredMinutes: anchoredMinutes,
                        stops: stopMinutes,
                        maxMinutes: maxMinutes
                    )
                }
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
                defer {
                    suppressCommit = false
                    wasOverscrolling = false
                }

                if suppressCommit {
                    withAnimation(TicketGaugeInk.snap) {
                        displayFraction = EstimateSnapMapping.fraction(
                            minutes: anchoredMinutes,
                            maxMinutes: maxMinutes
                        )
                        updateDragging(false)
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
                    updateDragging(false)
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
                    updateDragging(false)
                    onCommit?()
                } else {
                    withAnimation(TicketGaugeInk.snap) {
                        displayFraction = landed
                        updateDragging(false)
                    }
                    onCommit?()
                }
            }
    }

    private func applyEscape(to stop: Int, playHaptic: Bool, animated: Bool) {
        anchoredMinutes = stop
        minutes = stop
        if playHaptic {
            switch style {
            case .ticket:
                impactPulse += 1
            case .cabin:
                cabinSelectionPulse += 1
            }
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

    /// 発券の VoiceOver は点の振動に加え、選択のフィードバックも鳴らす。盤は点の選択だけ。
    private func noteAdjustableDetent(issuing: Bool) {
        if style == .ticket, !issuing {
            selectionPulse += 1
        }
        if style == .cabin {
            onCommit?()
        }
    }

    private func noteOverscroll(_ finger: CGFloat) {
        guard style == .cabin else { return }
        let over = EstimateSnapMapping.isOverscrolling(fingerFraction: finger)
        if over, !wasOverscrolling {
            overscrollPulse += 1
        }
        wasOverscrolling = over
    }

    private func updateDragging(_ dragging: Bool) {
        guard isDragging != dragging else { return }
        isDragging = dragging
        onTouchingChange?(dragging)
    }
}

private enum CabinGaugeInk {
    static let groove = Color(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255)
    static let hairline = Color.white.opacity(0.14)
    static let fill = Color.white.opacity(0.07)
    static let stop = Color.white.opacity(0.28)
    static let ring = Color.white.opacity(0.70)
    static let band = Color.white.opacity(0.08)
    static let bandLit = Color.white.opacity(0.16)
    static let knob = Color(red: 217.0 / 255, green: 217.0 / 255, blue: 217.0 / 255)
    static let knobEdge = Color.white
}

private struct EstimateSnapLongPress: ViewModifier {
    var enabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55, maximumDistance: 8)
                    .onEnded { _ in action() }
            )
        } else {
            content
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
