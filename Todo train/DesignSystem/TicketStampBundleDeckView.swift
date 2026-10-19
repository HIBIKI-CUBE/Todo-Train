//
//  TicketStampBundleDeckView.swift
//  Todo train
//
//  たたんだ扇は帯の隅。長押しか横ドラッグで弧に開き、指を離すと戻る。
//

import SwiftUI
import TodoTrainTicketUI

enum TicketStampBundleDeckStyle {
    /// 運行終了。たたんだ帯はタイムラインの下。開くと上に重なる。
    case shutdown
    /// 履歴 1 日。タップでビューア、長押しと横ドラッグでその場の扇。
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
    /// 長押しのあと横に固定しているあいだ、ビューアの縦操作を止める。
    var verticalGesturesLocked: Binding<Bool> = .constant(false)
    /// スクショ用。指定した spread で止める。
    var pinnedSpread: CGFloat? = nil
    /// 開閉の録画用。0 から 1 へ開いて戻す。
    var playsSpreadDemo: Bool = false
    /// 隅に置いた扇が収まってよい矩形。運行終了と履歴が渡す。
    /// 高さは下ボタンやタブバーを含んだ容器。`bottomObstacle` でその高さを渡す。
    var layoutViewport: CGSize = CGSize(width: 360, height: 640)
    /// 矩形の下端にある下ボタン、またはタブバー。
    var bottomObstacle: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread: CGFloat = 0
    @State private var focusPosition: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var fanOpened = false
    @State private var suppressNextTap = false
    @State private var selectionPulse = 0
    @State private var boundaryPulse = 0
    @State private var shuttleArmPulse = 0
    @State private var fanOpenPulse = 0
    @State private var shuttleDrive = ShuttleDrive()
    @State private var ignorePanEnd = false

    private var renderedSpread: CGFloat {
        if style == .viewer { return 1 }
        if playsSpreadDemo { return spread }
        if let pinnedSpread {
            return min(1, max(0, pinnedSpread))
        }
        return spread
    }

    var body: some View {
        Group {
            if stamps.isEmpty {
                Color.clear.frame(height: 0).accessibilityHidden(true)
            } else {
                deck
            }
        }
        .onAppear {
            guard !stamps.isEmpty else { return }
            focusIndex = min(max(0, focusIndex), stamps.count - 1)
            focusPosition = CGFloat(focusIndex)
        }
        .onChange(of: stamps.count) { _, count in
            focusIndex = min(focusIndex, max(0, count - 1))
            focusPosition = CGFloat(focusIndex)
        }
        .onChange(of: focusIndex) { _, newValue in
            let target = CGFloat(newValue)
            guard abs(focusPosition - target) > 1.2 else { return }
            withAnimation(cardAnimation) {
                focusPosition = target
            }
        }
        .onDisappear {
            finishShuttle(collapse: false)
        }
        .task {
            await playSpreadDemoIfNeeded()
        }
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: boundaryPulse)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: shuttleArmPulse)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: fanOpenPulse)
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
    }

    private var deck: some View {
        GeometryReader { geo in
            let fan = fittedFan(in: geo.size)
            Color.clear
                .overlay(alignment: .bottomTrailing) {
                    fanBody(fan: fan)
                }
                .contentShape(Rectangle())
            .onTapGesture {
                guard style == .historyStrip else { return }
                guard renderedSpread < 0.08, !shuttleDrive.engaged, !suppressNextTap else {
                    suppressNextTap = false
                    return
                }
                onOpenViewer?()
            }
            .simultaneousGesture(panGesture())
            .simultaneousGesture(shuttleGesture())
        }
        .frame(
            width: style == .viewer ? nil : TicketStampBundleLayout.collapsedFanSize.width,
            height: style == .viewer ? nil : TicketStampBundleLayout.collapsedFanSize.height
        )
        .frame(maxWidth: style == .viewer ? .infinity : nil, maxHeight: style == .viewer ? .infinity : nil)
    }

    /// 右下を固定し、券面が大きくなる分は上と左へ出す。
    @ViewBuilder
    private func fanBody(fan: TicketStampBundleLayout.ExpandedFan) -> some View {
        if reduceMotion, style != .viewer, pinnedSpread == nil, !playsSpreadDemo {
            ZStack(alignment: .bottomTrailing) {
                fanLayer(spread: 0, fan: fan)
                    .opacity(1 - renderedSpread)
                fanLayer(spread: 1, fan: fan)
                    .opacity(renderedSpread)
            }
        } else {
            fanLayer(spread: renderedSpread, fan: fan)
        }
    }

    private func fanLayer(spread: CGFloat, fan: TicketStampBundleLayout.ExpandedFan) -> some View {
        let compact = TicketStampBundleLayout.compactTicketSize()
        let ticket = TicketStampBundleLayout.ticketSize(compact: compact, expanded: fan.ticket, spread: spread)
        let radius = TicketStampBundleLayout.lerp(
            compact.width * TicketStampBundleLayout.compactRadiusRatio,
            fan.radius,
            spread
        )
        let pivot = TicketStampBundleLayout.pivot(
            ticketWidth: ticket.width,
            ticketHeight: ticket.height,
            radius: radius
        )
        let scale = ticket.width / TicketStampBundleLayout.baseWidth
        return ZStack(alignment: .bottomTrailing) {
            ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                let depth = TicketStampBundleLayout.visualDepth(
                    index: index,
                    focus: focusPosition,
                    drag: dragOffset
                )
                let angle = TicketStampBundleLayout.angleDegrees(
                    depth: depth,
                    spread: spread,
                    expandedStep: fan.stepDegrees
                )
                StampedMarsTicketFace(
                    stamp: stamp,
                    scale: scale,
                    showsLogLines: style == .viewer && abs(depth) < 0.45
                )
                .frame(width: ticket.width, height: ticket.height, alignment: .bottom)
                .rotationEffect(
                    .degrees(angle),
                    anchor: UnitPoint(
                        x: pivot.x / max(ticket.width, 1),
                        y: pivot.y / max(ticket.height, 1)
                    )
                )
                .opacity(cardOpacity(depth))
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                .compositingGroup()
                .onTapGesture {
                    guard style == .viewer else { return }
                    onSelect(stamp)
                }
                .accessibilityAddTraits(abs(depth) < 0.45 ? .isSelected : [])
                .accessibilityAction(named: "詳細") {
                    onSelect(stamp)
                }
                .zIndex(TicketStampBundleLayout.stackRank(index: index))
            }
        }
        .compositingGroup()
        .offset(
            x: -fan.cornerInset.width - TicketStampBundleLayout.safeMargin,
            y: -fan.cornerInset.height
        )
    }

    private func cardOpacity(_ depth: Double) -> Double {
        if depth < 0 {
            return max(0, 1 + depth)
        }
        let cap = Double(TicketStampBundleLayout.depthCap)
        if depth > cap {
            return max(0, 1 - (depth - cap))
        }
        return 1
    }

    private func fittedFan(in proposed: CGSize) -> TicketStampBundleLayout.ExpandedFan {
        let box: CGSize
        switch style {
        case .viewer:
            box = CGSize(
                width: max(proposed.width - TicketStampBundleLayout.safeMargin * 2, 80),
                height: max(proposed.height - TicketStampBundleLayout.safeMargin * 2, 80)
            )
        case .shutdown, .historyStrip:
            box = CGSize(
                width: max(layoutViewport.width, 80),
                height: max(layoutViewport.height, 80)
            )
        }
        let clearance = style == .viewer ? 0 : TicketStampBundleLayout.bottomClearance
        let obstacle = style == .viewer ? 0 : bottomObstacle
        return TicketStampBundleLayout.expandedFan(
            fittingWidth: box.width,
            fittingHeight: box.height,
            depth: TicketStampBundleLayout.depthCap,
            bottomObstacle: obstacle,
            bottomClearance: clearance
        )
    }

    private var cardAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.22, dampingFraction: 0.86)
    }

    private func openFan() {
        guard style != .viewer, pinnedSpread == nil, !playsSpreadDemo else { return }
        if !fanOpened {
            fanOpened = true
            fanOpenPulse += 1
        }
        guard spread < 0.98 else { return }
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: TicketStampBundleLayout.openSpringResponse, dampingFraction: 0.84)
        withAnimation(animation) {
            spread = 1
        }
    }

    private func collapseFan() {
        guard style != .viewer, pinnedSpread == nil, !playsSpreadDemo else { return }
        guard fanOpened || spread > 0.02 else { return }
        fanOpened = false
        suppressNextTap = true
        let newest = max(0, stamps.count - 1)
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: TicketStampBundleLayout.closeSpringResponse, dampingFraction: 0.9)
        if reduceMotion {
            withAnimation(animation) {
                spread = 0
            }
            snapFocusToNewest(newest)
        } else {
            withAnimation(animation) {
                spread = 0
            } completion: {
                snapFocusToNewest(newest)
            }
        }
    }

    private func snapFocusToNewest(_ newest: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            focusIndex = newest
            focusPosition = CGFloat(newest)
        }
    }

    private func playSpreadDemoIfNeeded() async {
        guard playsSpreadDemo, style != .viewer else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            spread = 1
        }
        try? await Task.sleep(for: .milliseconds(1100))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            spread = 0
        }
    }

    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if ignorePanEnd, !shuttleDrive.engaged {
                    ignorePanEnd = false
                }
                guard !shuttleDrive.engaged, !ignorePanEnd else { return }
                let horizontal = abs(value.translation.width) >= abs(value.translation.height)
                guard horizontal else { return }
                dragOffset = value.translation.width
                if abs(value.translation.width) > 8 {
                    suppressNextTap = true
                    openFan()
                }
            }
            .onEnded { value in
                if ignorePanEnd || shuttleDrive.engaged {
                    ignorePanEnd = false
                    finishShuttle(collapse: true)
                    return
                }
                let horizontal = abs(value.translation.width) >= abs(value.translation.height)
                if horizontal {
                    let steps = TicketStampBundleSwipe.steps(
                        translation: Double(value.translation.width),
                        velocity: Double(value.velocity.width),
                        threshold: 32,
                        flickVelocity: 900
                    )
                    let fast = abs(value.velocity.width) > 1200
                    applySteps(steps, fast: fast)
                }
                settleDrag()
                if horizontal {
                    collapseFan()
                }
            }
    }

    private func shuttleGesture() -> some Gesture {
        LongPressGesture(
            minimumDuration: TicketStampBundleSwipe.shuttleArmDuration,
            maximumDistance: 16
        )
        .sequenced(before: DragGesture(minimumDistance: 0))
        .onChanged { value in
            guard case .second(true, let drag) = value else { return }
            let dx = drag?.translation.width ?? 0
            if !shuttleDrive.engaged {
                shuttleDrive.engaged = true
                ignorePanEnd = true
                suppressNextTap = true
                verticalGesturesLocked.wrappedValue = true
                dragOffset = 0
                if style == .viewer {
                    shuttleArmPulse += 1
                } else {
                    openFan()
                }
                startShuttleLoop()
            }
            shuttleDrive.distance = Double(dx)
            dragOffset = dx
        }
        .onEnded { _ in
            guard shuttleDrive.engaged else { return }
            finishShuttle(collapse: true)
        }
    }

    private func startShuttleLoop() {
        shuttleDrive.task?.cancel()
        let drive = shuttleDrive
        drive.task = Task { @MainActor in
            var carry = 0.0
            var last = Date()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(32))
                } catch {
                    break
                }
                guard drive.engaged else { break }
                let now = Date()
                let elapsed = min(0.25, now.timeIntervalSince(last))
                last = now
                let rate = TicketStampBundleSwipe.shuttleCardsPerSecond(distance: drive.distance)
                let advanced = TicketStampBundleSwipe.shuttleAdvance(
                    rate: rate,
                    elapsed: elapsed,
                    carry: carry
                )
                carry = advanced.carry
                guard advanced.steps != 0 else { continue }
                let direction = advanced.steps > 0 ? 1 : -1
                let fast = TicketStampBundleSwipe.shuttleSuppressesPerCardHaptics(cardsPerSecond: rate)
                for _ in 0..<abs(advanced.steps) {
                    let before = focusIndex
                    stepFocus(by: direction, haptic: true, fast: fast)
                    if focusIndex == before {
                        carry = 0
                        break
                    }
                }
            }
        }
    }

    private func finishShuttle(collapse: Bool) {
        let wasEngaged = shuttleDrive.engaged
        shuttleDrive.engaged = false
        shuttleDrive.distance = 0
        shuttleDrive.task?.cancel()
        shuttleDrive.task = nil
        verticalGesturesLocked.wrappedValue = false
        settleDrag()
        if collapse, wasEngaged {
            collapseFan()
        }
    }

    private func settleDrag() {
        if reduceMotion {
            dragOffset = 0
        } else {
            withAnimation(.smooth(duration: 0.22)) {
                dragOffset = 0
            }
        }
    }

    private func applySteps(_ steps: Int, fast: Bool) {
        guard steps != 0 else { return }
        let direction = steps > 0 ? 1 : -1
        for _ in 0..<abs(steps) {
            stepFocus(by: direction, haptic: true, fast: fast)
        }
    }

    private func stepFocus(by delta: Int, haptic: Bool, fast: Bool = false) {
        let next = min(max(0, focusIndex + delta), max(0, stamps.count - 1))
        guard next != focusIndex else { return }
        let crossedBoundary = dayBoundaries.contains(next)
        focusIndex = next
        withAnimation(cardAnimation) {
            focusPosition = CGFloat(next)
        }
        guard haptic else { return }
        if fast {
            if crossedBoundary { boundaryPulse += 1 }
        } else if crossedBoundary {
            boundaryPulse += 1
        } else {
            selectionPulse += 1
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

private final class ShuttleDrive {
    var distance: Double = 0
    var engaged = false
    var task: Task<Void, Never>?
}
