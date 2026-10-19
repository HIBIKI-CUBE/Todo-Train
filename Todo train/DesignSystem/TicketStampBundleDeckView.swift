//
//  TicketStampBundleDeckView.swift
//  Todo train
//
//  たたんだ扇は帯の隅。触れた瞬間に弧へ開き、指を離すと畳む。
//

import SwiftUI
import UIKit
import TodoTrainTicketUI

enum TicketStampBundleDeckStyle {
    /// 運行終了。たたんだ帯はタイムラインの下。開くと前面に重なる。
    case shutdown
    /// 履歴 1 日。短いタップでビューア、横になぞるとその場の扇。
    case historyStrip
    /// 全画面ビューア。扇は開いたまま。
    case viewer
}

struct TicketStampBundleSpreadPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TicketStampBundleDeckView: View {
    var stamps: [TicketStampBundleAssembly.Stamp]
    @Binding var focusIndex: Int
    var style: TicketStampBundleDeckStyle
    var dayBoundaries: Set<Int> = []
    var onSelect: (TicketStampBundleAssembly.Stamp) -> Void = { _ in }
    var onOpenViewer: (() -> Void)? = nil
    /// 横と決めたあいだ、ビューアの縦操作を止める。
    var verticalGesturesLocked: Binding<Bool> = .constant(false)
    /// 指が乗っているあいだ true。履歴の日送りを止める。
    var bundleTouching: Binding<Bool> = .constant(false)
    /// スクショ用。指定した spread で止める。
    var pinnedSpread: CGFloat? = nil
    /// スクショ用。0 が最古、1 が最新。
    var pinnedFocusUnit: CGFloat? = nil
    /// 開閉の録画用。開いて、最古までなぞって、最新側へなぞって、畳む。
    var playsSpreadDemo: Bool = false
    /// 画面内の下ボタン。タブバーは安全領域の下端に含める。
    var bottomObstacle: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var spread: CGFloat = 0
    @State private var focusPosition: CGFloat = 0
    @State private var liftedFocus: CGFloat = 0
    @State private var fanSession = TicketStampBundleFanSession.closed
    @State private var selectionPulse = 0
    @State private var boundaryPulse = 0
    @State private var fanOpenPulse = 0
    @State private var viewportWidth: CGFloat = 390
    @State private var touch = TouchTracking()
    /// `ignoresSafeArea` の GeometryReader は下端を 0 にする。UIKit の値を使う。
    @State private var safeInsets = EdgeInsets()
    @State private var didMeasureSafeArea = false
    @GestureState private var isTouching = false

    private var renderedSpread: CGFloat {
        if playsSpreadDemo { return spread }
        if let pinnedSpread {
            return min(1, max(0, pinnedSpread))
        }
        if style == .viewer { return 1 }
        return spread
    }

    private var gesturesEnabled: Bool {
        pinnedSpread == nil && pinnedFocusUnit == nil && !playsSpreadDemo
    }

    var body: some View {
        GeometryReader { geo in
            let screen = makeScreen(geo)
            fanStack(screen: screen)
                .background {
                    TicketStampBundleSafeAreaProbe { insets in
                        if insets != safeInsets {
                            safeInsets = insets
                        }
                        if !didMeasureSafeArea {
                            didMeasureSafeArea = true
                        }
                    }
                }
                .onAppear { viewportWidth = screen.width }
                .onChange(of: screen.width) { _, width in
                    viewportWidth = width
                }
        }
        .onAppear(perform: alignFocus)
        .onChange(of: stampIDs) { _, _ in
            focusIndex = min(focusIndex, max(0, stamps.count - 1))
            endSession(.bundleChanged, animated: false)
        }
        .onChange(of: focusIndex) { _, newValue in
            guard !touch.active, pinnedFocusUnit == nil else { return }
            let target = CGFloat(newValue)
            guard abs(focusPosition - target) > 1.2 else { return }
            let animation: Animation = reduceMotion
                ? .easeInOut(duration: 0.15)
                : .interactiveSpring(
                    response: TicketStampBundleLayout.liftSpringResponse,
                    dampingFraction: TicketStampBundleLayout.liftSpringDamping
                )
            withAnimation(animation) {
                focusPosition = target
                liftedFocus = target
            }
        }
        .onChange(of: isTouching) { _, touching in
            bundleTouching.wrappedValue = touching
            guard !touching else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                guard touch.active else { return }
                if touch.pendingRelease != nil {
                    commitRelease()
                } else {
                    touch.active = false
                    verticalGesturesLocked.wrappedValue = false
                    endSession(.cancelled, animated: true)
                }
            }
        }
        .onDisappear {
            bundleTouching.wrappedValue = false
            endSession(.disappeared, animated: false)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            bundleTouching.wrappedValue = false
            endSession(.sceneInactive, animated: false)
        }
        .task {
            await playSpreadDemoIfNeeded()
        }
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: boundaryPulse)
        .sensoryFeedback(.impact(weight: .light, intensity: 1), trigger: fanOpenPulse)
        .accessibilityElement(children: .contain)
        .accessibilityValue(stamps.isEmpty ? "" : "\(focusIndex + 1)枚目、全\(stamps.count)枚")
        .modifier(DeckSwipeHint(enabled: style != .historyStrip))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                stepFocus(by: 1, haptic: true)
            case .decrement:
                stepFocus(by: -1, haptic: true)
            default:
                break
            }
        }
        .preference(key: TicketStampBundleSpreadPreference.self, value: renderedSpread)
        .accessibilityIdentifier(renderedSpread > 0.85 ? "ticket-stamp-bundle-open" : "ticket-stamp-bundle")
    }

    private var stampIDs: [UUID] {
        stamps.map(\.sessionID)
    }

    private func makeScreen(_ geo: GeometryProxy) -> TicketStampBundleLayout.Screen {
        TicketStampBundleLayout.Screen(
            width: geo.size.width,
            height: geo.size.height,
            safeTop: safeInsets.top,
            safeLeading: safeInsets.leading,
            safeTrailing: safeInsets.trailing,
            safeBottom: safeInsets.bottom,
            bottomObstacle: bottomObstacle,
            hubColumnWidth: TicketStampBundleLayout.hubColumnWidth(
                containerWidth: geo.size.width,
                compactHeight: verticalSizeClass == .compact
            )
        )
    }

    private func fanStack(screen: TicketStampBundleLayout.Screen) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .allowsHitTesting(false)
            interactiveFan(screen: screen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(didMeasureSafeArea ? 1 : 0)
    }

    @ViewBuilder
    private func interactiveFan(screen: TicketStampBundleLayout.Screen) -> some View {
        if gesturesEnabled {
            fanBody(screen: screen)
                .simultaneousGesture(fanGesture(screen: screen))
        } else {
            fanBody(screen: screen)
        }
    }

    @ViewBuilder
    private func fanBody(screen: TicketStampBundleLayout.Screen) -> some View {
        if reduceMotion, style != .viewer, pinnedSpread == nil, !playsSpreadDemo {
            ZStack {
                fanLayer(spread: 0, screen: screen)
                    .opacity(1 - renderedSpread)
                fanLayer(spread: 1, screen: screen)
                    .opacity(renderedSpread)
            }
        } else {
            fanLayer(spread: renderedSpread, screen: screen)
        }
    }

    private func fanLayer(spread: CGFloat, screen: TicketStampBundleLayout.Screen) -> some View {
        let count = max(stamps.count, 1)
        let placement = TicketStampBundleLayout.placement(spread: spread, count: count, screen: screen)
        let focus = shownFocus
        let ticket = placement.ticket
        let scale = ticket.width / TicketStampBundleLayout.baseWidth
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                let lift = TicketStampBundleLayout.lift(index: index, focus: focus)
                let pull = TicketStampBundleLayout.liftOffset(
                    index: index,
                    focus: focus,
                    count: count,
                    placement: placement,
                    safeRect: screen.safeRect
                )
                let angle = TicketStampBundleLayout.angle(
                    index: index,
                    count: count,
                    step: placement.step
                )
                let inFront = TicketStampBundleLayout.liftsToFront(
                    index: index,
                    focus: focus,
                    count: count
                )
                StampedMarsTicketFace(
                    stamp: stamp,
                    scale: scale,
                    showsLogLines: style == .viewer && inFront
                )
                .frame(width: ticket.width, height: ticket.height, alignment: .bottom)
                .rotationEffect(
                    .degrees(angle),
                    anchor: UnitPoint(
                        x: placement.pivot.x / max(ticket.width, 1),
                        y: placement.pivot.y / max(ticket.height, 1)
                    )
                )
                .offset(x: pull.width, y: pull.height)
                .shadow(
                    color: .black.opacity(0.10 + 0.14 * lift),
                    radius: 2 + 6 * lift,
                    y: 1 + 3 * lift
                )
                .compositingGroup()
                .accessibilityAddTraits(inFront ? .isSelected : [])
                .accessibilityAction(named: "詳細") {
                    onSelect(stamp)
                }
                .zIndex(
                    (inFront ? 1_000 : 0) + TicketStampBundleLayout.stackRank(index: index)
                )
            }
        }
        .frame(width: ticket.width, height: ticket.height, alignment: .topLeading)
        .position(
            x: placement.frontOrigin.x + ticket.width / 2,
            y: placement.frontOrigin.y + ticket.height / 2
        )
    }

    private var shownFocus: CGFloat {
        guard !stamps.isEmpty else { return 0 }
        if let pinnedFocusUnit {
            let newest = CGFloat(stamps.count - 1)
            return min(1, max(0, pinnedFocusUnit)) * newest
        }
        return liftedFocus
    }

    private func fanGesture(screen: TicketStampBundleLayout.Screen) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isTouching) { _, state, _ in
                state = true
            }
            .onChanged { value in
                handleTouchChange(value, screen: screen)
            }
            .onEnded { value in
                touch.pendingRelease = ReleaseSample(
                    translation: value.translation,
                    velocity: value.velocity,
                    duration: Date().timeIntervalSince(touch.startedAt)
                )
                if !isTouching {
                    commitRelease()
                }
            }
    }

    private func handleTouchChange(
        _ value: DragGesture.Value,
        screen: TicketStampBundleLayout.Screen
    ) {
        if !touch.active {
            touch.momentum?.cancel()
            touch.momentum = nil
            touch.active = true
            touch.startedAt = Date()
            touch.startFocus = focusPosition
            touch.axis = nil
            touch.pendingRelease = nil
            touch.didOpenHaptic = false
            touch.didAnimateOpen = false
            bundleTouching.wrappedValue = true
            fanSession = TicketStampBundleFanSession.reduce(fanSession, .touchBegan)
            openFan()
        } else {
            fanSession = TicketStampBundleFanSession.reduce(fanSession, .moved)
        }
        let dx = value.translation.width
        let dy = value.translation.height
        if touch.axis == nil, hypot(dx, dy) >= TicketStampBundleGesture.axisDecisionDistance {
            touch.axis = abs(dx) >= abs(dy) ? .horizontal : .vertical
            if touch.axis == .horizontal, style == .viewer {
                verticalGesturesLocked.wrappedValue = true
            }
        }
        guard touch.axis == .horizontal else { return }
        let next = TicketStampBundleLayout.focus(
            start: touch.startFocus,
            translation: dx,
            travelPerCard: TicketStampBundleLayout.travelPerCard(
                viewportWidth: screen.width,
                count: stamps.count
            ),
            count: stamps.count
        )
        let previous = focusPosition
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            focusPosition = next
            focusIndex = Int(next.rounded())
        }
        if reduceMotion {
            liftedFocus = next
        } else {
            withAnimation(
                .interactiveSpring(
                    response: TicketStampBundleLayout.liftSpringResponse,
                    dampingFraction: TicketStampBundleLayout.liftSpringDamping
                )
            ) {
                liftedFocus = next
            }
        }
        pulseCrossings(from: previous, to: next)
    }

    private func commitRelease() {
        guard touch.active else { return }
        touch.active = false
        let sample = touch.pendingRelease
        touch.pendingRelease = nil
        verticalGesturesLocked.wrappedValue = false
        let axis = sessionAxis(for: sample)
        fanSession = TicketStampBundleFanSession.reduce(fanSession, .ended(axis))
        guard let sample else {
            collapseUnlessViewer(animated: true)
            return
        }
        let kind = TicketStampBundleGesture.classify(
            dx: Double(sample.translation.width),
            dy: Double(sample.translation.height),
            duration: sample.duration
        )
        switch style {
        case .viewer:
            if kind == .tap {
                selectShownStamp()
            } else if kind == .horizontal {
                beginMomentum(velocity: sample.velocity.width)
            }
        case .historyStrip:
            collapseFan(animated: true)
            if kind == .tap {
                onOpenViewer?()
            }
        case .shutdown:
            collapseFan(animated: true)
        }
    }

    private func sessionAxis(for sample: ReleaseSample?) -> TicketStampBundleFanSession.Axis {
        guard let sample else { return .undecided }
        switch TicketStampBundleGesture.classify(
            dx: Double(sample.translation.width),
            dy: Double(sample.translation.height),
            duration: sample.duration
        ) {
        case .horizontal:
            return .horizontal
        case .vertical:
            return .vertical
        case .tap, .pending:
            return .undecided
        }
    }

    private func selectShownStamp() {
        guard !stamps.isEmpty else { return }
        let count = stamps.count
        if let index = stamps.indices.first(where: {
            TicketStampBundleLayout.liftsToFront(index: $0, focus: shownFocus, count: count)
        }) {
            onSelect(stamps[index])
            return
        }
        let index = min(max(0, Int(shownFocus.rounded())), count - 1)
        onSelect(stamps[index])
    }

    private func beginMomentum(velocity: CGFloat) {
        let travel = TicketStampBundleLayout.travelPerCard(
            viewportWidth: viewportWidth,
            count: stamps.count
        )
        let target = TicketStampBundleGesture.projectedFocus(
            focus: Double(focusPosition),
            velocity: Double(velocity),
            travelPerCard: Double(travel),
            count: stamps.count
        )
        let from = focusPosition
        let destination = CGFloat(target)
        if reduceMotion {
            focusPosition = destination
            liftedFocus = destination
            focusIndex = target
            pulseCrossings(from: from, to: destination)
            return
        }
        withAnimation(
            .spring(
                response: TicketStampBundleGesture.momentumSpringResponse,
                dampingFraction: TicketStampBundleGesture.momentumSpringDamping
            )
        ) {
            focusPosition = destination
            liftedFocus = destination
            focusIndex = target
        }
        let marks = TicketStampBundleGesture.crossings(from: Double(from), to: Double(destination))
        guard !marks.isEmpty else { return }
        touch.momentum?.cancel()
        touch.momentum = Task { @MainActor in
            let gap = max(
                TicketStampBundleGesture.hapticMinInterval,
                TicketStampBundleGesture.momentumSpringResponse / Double(marks.count)
            )
            for mark in marks {
                try? await Task.sleep(for: .seconds(gap))
                guard !Task.isCancelled, !touch.active else { return }
                pulseBoundaryOrSelection(mark)
            }
        }
    }

    private func endSession(_ event: TicketStampBundleFanSession.Event, animated: Bool) {
        touch.active = false
        touch.pendingRelease = nil
        touch.momentum?.cancel()
        touch.momentum = nil
        verticalGesturesLocked.wrappedValue = false
        fanSession = TicketStampBundleFanSession.reduce(fanSession, event)
        collapseUnlessViewer(animated: animated)
    }

    private func collapseUnlessViewer(animated: Bool) {
        guard style != .viewer else { return }
        collapseFan(animated: animated)
    }

    private func alignFocus() {
        guard !stamps.isEmpty else { return }
        let newest = stamps.count - 1
        let initial: CGFloat
        if let pinnedFocusUnit {
            initial = min(1, max(0, pinnedFocusUnit)) * CGFloat(newest)
        } else {
            initial = CGFloat(min(max(0, focusIndex), newest))
        }
        focusIndex = Int(initial.rounded())
        focusPosition = initial
        liftedFocus = initial
    }

    private func openFan() {
        guard style != .viewer, pinnedSpread == nil, !playsSpreadDemo else { return }
        if !touch.didOpenHaptic {
            touch.didOpenHaptic = true
            fanOpenPulse += 1
        }
        guard !touch.didAnimateOpen, spread < 0.98 else { return }
        touch.didAnimateOpen = true
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(
                response: TicketStampBundleLayout.openSpringResponse,
                dampingFraction: TicketStampBundleLayout.openSpringDamping
            )
        withAnimation(animation) {
            spread = 1
        }
    }

    private func collapseFan(animated: Bool) {
        guard style != .viewer, pinnedSpread == nil, !playsSpreadDemo else { return }
        let newest = max(0, stamps.count - 1)
        let alreadyClosed = spread <= 0.001
            && focusIndex == newest
            && abs(focusPosition - CGFloat(newest)) < 0.001
            && abs(liftedFocus - CGFloat(newest)) < 0.001
        fanSession = .closed
        guard !alreadyClosed else { return }
        if animated {
            let animation: Animation = reduceMotion
                ? .easeInOut(duration: 0.15)
                : .spring(
                    response: TicketStampBundleLayout.closeSpringResponse,
                    dampingFraction: TicketStampBundleLayout.closeSpringDamping
                )
            withAnimation(animation) {
                spread = 0
            } completion: {
                guard !touch.active else { return }
                snapFocusToNewest(newest)
            }
            if reduceMotion {
                snapFocusToNewest(newest)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                spread = 0
                snapFocusToNewest(newest)
            }
        }
    }

    private func snapFocusToNewest(_ newest: Int) {
        focusIndex = newest
        focusPosition = CGFloat(newest)
        liftedFocus = CGFloat(newest)
    }

    private func playSpreadDemoIfNeeded() async {
        guard playsSpreadDemo, style != .viewer, !stamps.isEmpty else { return }
        let newest = CGFloat(stamps.count - 1)
        focusPosition = newest
        liftedFocus = newest
        focusIndex = Int(newest.rounded())
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, scenePhase == .active else { return }
        withAnimation(
            .spring(
                response: TicketStampBundleLayout.openSpringResponse,
                dampingFraction: TicketStampBundleLayout.openSpringDamping
            )
        ) {
            spread = 1
        }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, scenePhase == .active else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            focusPosition = 0
            liftedFocus = 0
            focusIndex = 0
        }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled, scenePhase == .active else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            focusPosition = newest
            liftedFocus = newest
            focusIndex = Int(newest.rounded())
        }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, scenePhase == .active else { return }
        withAnimation(
            .spring(
                response: TicketStampBundleLayout.closeSpringResponse,
                dampingFraction: TicketStampBundleLayout.closeSpringDamping
            )
        ) {
            spread = 0
        }
    }

    private func stepFocus(by delta: Int, haptic: Bool) {
        let next = min(max(0, focusIndex + delta), max(0, stamps.count - 1))
        guard next != focusIndex else { return }
        let previous = focusPosition
        let crossed = dayBoundaries.contains(next)
        focusIndex = next
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .interactiveSpring(
                response: TicketStampBundleLayout.liftSpringResponse,
                dampingFraction: TicketStampBundleLayout.liftSpringDamping
            )
        withAnimation(animation) {
            focusPosition = CGFloat(next)
            liftedFocus = CGFloat(next)
        }
        guard haptic else { return }
        if crossed {
            boundaryPulse += 1
            touch.lastHaptic = Date()
        } else if previous != CGFloat(next) {
            selectionPulse += 1
            touch.lastHaptic = Date()
        }
    }

    private func pulseCrossings(from start: CGFloat, to end: CGFloat) {
        for mark in TicketStampBundleGesture.crossings(from: Double(start), to: Double(end)) {
            pulseBoundaryOrSelection(mark)
        }
    }

    private func pulseBoundaryOrSelection(_ mark: Int) {
        if dayBoundaries.contains(mark) {
            boundaryPulse += 1
            touch.lastHaptic = Date()
            return
        }
        let now = Date()
        guard now.timeIntervalSince(touch.lastHaptic) >= TicketStampBundleGesture.hapticMinInterval else {
            return
        }
        selectionPulse += 1
        touch.lastHaptic = now
    }
}

private struct TouchTracking {
    var active = false
    var startedAt = Date()
    var startFocus: CGFloat = 0
    var axis: TicketStampBundleFanSession.Axis?
    var pendingRelease: ReleaseSample?
    var didOpenHaptic = false
    var didAnimateOpen = false
    var lastHaptic = Date.distantPast
    var momentum: Task<Void, Never>?
}

private struct ReleaseSample {
    var translation: CGSize
    var velocity: CGSize
    var duration: TimeInterval
}

/// 全面に広げた扇でも、タブバーやホームインジケータの内側を知る。
private struct TicketStampBundleSafeAreaProbe: UIViewRepresentable {
    var onChange: (EdgeInsets) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.report()
    }

    final class ProbeView: UIView {
        var onChange: (EdgeInsets) -> Void = { _ in }
        private var last = EdgeInsets()

        func report() {
            let next = EdgeInsets(
                top: safeAreaInsets.top,
                leading: safeAreaInsets.left,
                bottom: safeAreaInsets.bottom,
                trailing: safeAreaInsets.right
            )
            guard next != last else { return }
            last = next
            let deliver = onChange
            DispatchQueue.main.async {
                deliver(next)
            }
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }
    }
}

private struct DeckSwipeHint: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityHint(
                "右になぞると古い切符、左になぞると新しい切符です。増やすと新しい切符、減らすと古い切符です。"
            )
        } else {
            content
        }
    }
}
