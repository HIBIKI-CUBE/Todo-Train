//
//  TicketStampBundleDeckView.swift
//  Todo train
//
//  奥の切符は上にのぞく。横になぞると一枚、長押しのあと距離で連続。
//

import SwiftUI
import TodoTrainTicketUI
import UIKit

enum TicketStampBundleDeckStyle {
    /// 運行終了。横になぞって一枚ずつ。幅・高さに収める。
    case shutdown
    /// 履歴 1 日。小さな束、タップのみ。奥は 2 枚まで。
    case historyStrip
    /// 全画面ビューア。横になぞり、幅 8 割。
    case viewer
}

struct TicketStampBundleDeckView: View {
    var stamps: [TicketStampBundleAssembly.Stamp]
    @Binding var focusIndex: Int
    var style: TicketStampBundleDeckStyle
    var dayBoundaries: Set<Int> = []
    var onSelect: (TicketStampBundleAssembly.Stamp) -> Void = { _ in }
    /// 長押しのあと横に固定しているあいだ、ビューアの縦操作を止める。
    var verticalGesturesLocked: Binding<Bool> = .constant(false)
    /// 運行終了でタイムラインを残すために浅くした奥行き。
    var shutdownDepthCap: Int? = nil
    /// 運行終了の券面。帯の中でさらに縮めない。
    var shutdownTicket: TicketStampBundleLayout.TicketSize? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var dragOffset: CGFloat = 0
    @State private var selectionPulse = 0
    @State private var boundaryPulse = 0
    @State private var shuttleArmPulse = 0
    @State private var shuttleDrive = ShuttleDrive()
    @State private var ignorePanEnd = false

    /// 横向きの履歴はタブの上に収める。帯は券面 × (1 + 0.45 × 2)。
    private var historyTicketHeight: CGFloat {
        if verticalSizeClass == .compact {
            return 64
        }
        return TicketStampBundleLayout.historyTicketHeight
    }

    private var historyTicketWidth: CGFloat {
        historyTicketHeight * MarsTicketSpec.aspectWidth / MarsTicketSpec.aspectHeight
    }

    private var maxFanDepth: Int {
        let standard = TicketStampBundleLayout.maxFanDepth(for: style)
        guard style == .shutdown, let cap = shutdownDepthCap else { return standard }
        return min(standard, max(0, cap))
    }

    /// 帯と券面の縮尺。手前が最新のときの奥行きで固定し、めくるたびに高さが変わらない。
    private var layoutDepth: Int {
        TicketStampBundleLayout.stackDepth(
            stampCount: stamps.count,
            focusIndex: max(0, stamps.count - 1),
            style: style
        )
    }

    /// `focusIndex` = いま手前の切符（古い方から数える）。奥は上。
    private var visibleStamps: [TicketStampBundleAssembly.Stamp] {
        let end = min(focusIndex + 1, stamps.count)
        guard end > 0 else { return [] }
        let start = max(0, end - (maxFanDepth + 1))
        return Array(stamps[start..<end])
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
            if !stamps.isEmpty {
                focusIndex = min(max(0, focusIndex), stamps.count - 1)
            }
        }
        .onChange(of: stamps.count) { _, count in
            focusIndex = min(focusIndex, max(0, count - 1))
        }
        .onDisappear {
            finishShuttle()
        }
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: boundaryPulse)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: shuttleArmPulse)
        .accessibilityElement(children: .contain)
        .accessibilityValue(stamps.isEmpty ? "" : "\(focusIndex + 1)枚目、全\(stamps.count)枚")
        .modifier(DeckSwipeHint(enabled: style != .historyStrip))
        .accessibilityAdjustableAction { direction in
            guard style != .historyStrip else { return }
            switch direction {
            case .increment:
                stepFocus(by: 1, haptic: true)
            case .decrement:
                stepFocus(by: -1, haptic: true)
            default:
                break
            }
        }
    }

    private var deck: some View {
        GeometryReader { geo in
            let metrics = layoutMetrics(in: geo.size)
            ZStack {
                ForEach(Array(visibleStamps.enumerated()), id: \.element.id) { offset, stamp in
                    let depth = visibleStamps.count - 1 - offset
                    let isFront = depth == 0
                    let showsLogs = isFront && style == .viewer
                    StampedMarsTicketFace(stamp: stamp, scale: metrics.scale, showsLogLines: showsLogs)
                        .frame(width: metrics.ticketWidth, height: metrics.ticketHeight, alignment: .bottom)
                        .offset(TicketStampBundleLayout.offset(
                            depth: depth,
                            ticketHeight: metrics.ticketHeight,
                            drag: dragOffset
                        ))
                        .zIndex(Double(offset))
                        .onTapGesture {
                            onSelect(stamp)
                        }
                        .accessibilityAddTraits(isFront ? .isSelected : [])
                        .accessibilityAction(named: "詳細") {
                            onSelect(stamp)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .simultaneousGesture(style == .historyStrip ? nil : panGesture())
            .simultaneousGesture(style == .historyStrip ? nil : shuttleGesture())
        }
        .modifier(DeckBandHeightModifier(
            style: style,
            bandHeight: TicketStampBundleLayout.bandHeight(
                ticketHeight: historyTicketHeight,
                depth: layoutDepth
            )
        ))
        .clipped()
    }

    private struct DeckBandHeightModifier: ViewModifier {
        var style: TicketStampBundleDeckStyle
        var bandHeight: CGFloat

        func body(content: Content) -> some View {
            switch style {
            case .shutdown, .viewer:
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .historyStrip:
                content.frame(height: bandHeight)
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

    private struct LayoutMetrics {
        var ticketWidth: CGFloat
        var ticketHeight: CGFloat
        var scale: CGFloat
    }

    private func layoutMetrics(in size: CGSize) -> LayoutMetrics {
        switch style {
        case .shutdown:
            if let ticket = shutdownTicket {
                return LayoutMetrics(
                    ticketWidth: ticket.width,
                    ticketHeight: ticket.height,
                    scale: ticket.scale
                )
            }
            let fitted = TicketStampBundleLayout.fittedTicketSize(
                targetWidth: TicketStampBundleLayout.shutdownTargetWidth(containerWidth: size.width),
                viewportHeight: size.height,
                depth: layoutDepth
            )
            return LayoutMetrics(
                ticketWidth: fitted.width,
                ticketHeight: fitted.height,
                scale: fitted.scale
            )
        case .historyStrip:
            return LayoutMetrics(
                ticketWidth: historyTicketWidth,
                ticketHeight: historyTicketHeight,
                scale: historyTicketWidth / TicketStampBundleLayout.baseWidth
            )
        case .viewer:
            let fitted = TicketStampBundleLayout.fittedTicketSize(
                targetWidth: size.width * 0.8,
                viewportHeight: size.height,
                depth: layoutDepth
            )
            return LayoutMetrics(
                ticketWidth: fitted.width,
                ticketHeight: fitted.height,
                scale: fitted.scale
            )
        }
    }

    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if ignorePanEnd, !shuttleDrive.engaged {
                    ignorePanEnd = false
                }
                guard !shuttleDrive.engaged, !ignorePanEnd else { return }
                if abs(value.translation.width) >= abs(value.translation.height) {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                if ignorePanEnd || shuttleDrive.engaged {
                    ignorePanEnd = false
                    finishShuttle()
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
                shuttleArmPulse += 1
                verticalGesturesLocked.wrappedValue = true
                dragOffset = 0
                startShuttleLoop()
            }
            shuttleDrive.distance = Double(dx)
            dragOffset = dx
        }
        .onEnded { _ in
            guard shuttleDrive.engaged else { return }
            finishShuttle()
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

    private func finishShuttle() {
        shuttleDrive.engaged = false
        shuttleDrive.distance = 0
        shuttleDrive.task?.cancel()
        shuttleDrive.task = nil
        verticalGesturesLocked.wrappedValue = false
        settleDrag()
    }

    private func settleDrag() {
        if reduceMotion {
            dragOffset = 0
        } else {
            withAnimation(.smooth(duration: 0.28)) {
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
        guard haptic else { return }
        if fast {
            if crossedBoundary { boundaryPulse += 1 }
        } else if crossedBoundary {
            boundaryPulse += 1
        } else {
            selectionPulse += 1
        }
    }

    /// 運行終了の束帯の高さ。呼び出し側が時計の下限で頭を抑える。
    static func shutdownBandHeight(
        containerWidth: CGFloat,
        bandViewportHeight: CGFloat,
        depth: Int
    ) -> CGFloat {
        let ticket = TicketStampBundleLayout.fittedTicketSize(
            targetWidth: TicketStampBundleLayout.shutdownTargetWidth(containerWidth: containerWidth),
            viewportHeight: bandViewportHeight,
            depth: depth
        )
        return TicketStampBundleLayout.bandHeight(ticketHeight: ticket.height, depth: depth)
    }
}

private final class ShuttleDrive {
    var distance: Double = 0
    var engaged = false
    var task: Task<Void, Never>?
}
