//
//  TicketStampBundleDeckView.swift
//  Todo train
//

import SwiftUI
import TodoTrainTicketUI
import UIKit

enum TicketStampBundleDeckStyle {
    /// 運行終了。横になぞって一枚ずつ。幅・高さに収める。
    case shutdown
    /// 履歴 1 日。小さな扇、タップのみ。
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var selectionPulse = 0
    @State private var boundaryPulse = 0

    private static let fanStep: CGFloat = 16
    private static let fanDegrees: Double = 4
    private static let maxFanDepth = 4
    private static let maxVisibleCards = 5

    /// `focusIndex` = いま手前の切符（古い方から数える）。扇は手前 + 奥 4 枚まで。
    private var visibleStamps: [TicketStampBundleAssembly.Stamp] {
        let end = min(focusIndex + 1, stamps.count)
        guard end > 0 else { return [] }
        let start = max(0, end - Self.maxVisibleCards)
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
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: boundaryPulse)
        .accessibilityElement(children: .contain)
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
            let centerNudge = fanCenterNudge(metrics: metrics)
            let alignment: Alignment = style == .historyStrip ? .bottomLeading : .bottom
            ZStack {
                ForEach(Array(visibleStamps.enumerated()), id: \.element.id) { offset, stamp in
                    let depth = visibleStamps.count - 1 - offset
                    let isFront = depth == 0
                    let showsLogs = isFront && style == .viewer
                    StampedMarsTicketFace(stamp: stamp, scale: metrics.scale, showsLogLines: showsLogs)
                        .frame(width: metrics.ticketWidth, height: metrics.ticketHeight, alignment: .bottom)
                        .rotationEffect(
                            .degrees(fanRotation(depth: depth)),
                            anchor: .bottom
                        )
                        .offset(fanOffset(depth: depth, drag: dragOffset))
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
            .offset(x: centerNudge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .contentShape(Rectangle())
            .gesture(style == .historyStrip ? nil : panGesture(metrics: metrics))
        }
        .modifier(DeckBandHeightModifier(style: style))
        .clipped()
    }

    private struct DeckBandHeightModifier: ViewModifier {
        var style: TicketStampBundleDeckStyle

        func body(content: Content) -> some View {
            switch style {
            case .shutdown:
                content.frame(maxHeight: .infinity)
            case .historyStrip:
                content.frame(height: 140)
            case .viewer:
                content.frame(height: 280)
            }
        }
    }

    private struct LayoutMetrics {
        var ticketWidth: CGFloat
        var ticketHeight: CGFloat
        var scale: CGFloat
    }

    private func layoutMetrics(in size: CGSize) -> LayoutMetrics {
        let baseWidth: CGFloat = 300
        switch style {
        case .shutdown:
            let targetW = min(size.width * 0.72, 340)
            var scale = targetW / baseWidth
            var ticketH = MarsTicketSpec.height(forWidth: baseWidth) * scale
            let maxH = max(72, size.height - 10)
            if ticketH > maxH {
                scale = maxH / MarsTicketSpec.height(forWidth: baseWidth)
                ticketH = maxH
            }
            return LayoutMetrics(
                ticketWidth: baseWidth * scale,
                ticketHeight: ticketH,
                scale: scale
            )
        case .historyStrip:
            let ticketW: CGFloat = 200
            let ticketH: CGFloat = 110
            return LayoutMetrics(
                ticketWidth: ticketW,
                ticketHeight: ticketH,
                scale: ticketW / baseWidth
            )
        case .viewer:
            let targetW = size.width * 0.8
            let scale = min(targetW / baseWidth, 1)
            return LayoutMetrics(
                ticketWidth: baseWidth * scale,
                ticketHeight: MarsTicketSpec.height(forWidth: baseWidth) * scale,
                scale: scale
            )
        }
    }

    private func fanRotation(depth: Int) -> Double {
        let capped = min(depth, Self.maxFanDepth)
        guard capped > 0 else { return 0 }
        return -Double(capped) * Self.fanDegrees
    }

    private func fanOffset(depth: Int, drag: CGFloat) -> CGSize {
        let capped = min(depth, Self.maxFanDepth)
        let primary = -CGFloat(capped) * Self.fanStep + drag * 0.28
        return CGSize(width: primary, height: CGFloat(capped) * 1.5)
    }

    private func fanCenterNudge(metrics: LayoutMetrics) -> CGFloat {
        guard style == .shutdown || style == .viewer else { return 0 }
        let depth = min(max(0, visibleStamps.count - 1), Self.maxFanDepth)
        return CGFloat(depth) * Self.fanStep * 0.5
    }

    private func panGesture(metrics: LayoutMetrics) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let delta = value.translation.width
                let velocity = value.velocity.width
                let threshold: CGFloat = 32
                var steps = 0
                if abs(velocity) > 900 {
                    steps = velocity > 0 ? -1 : 1
                } else if delta > threshold {
                    steps = 1
                } else if delta < -threshold {
                    steps = -1
                }
                let fast = abs(velocity) > 1200
                applySteps(steps, fast: fast)
                if reduceMotion {
                    dragOffset = 0
                } else {
                    withAnimation(.smooth(duration: 0.28)) {
                        dragOffset = 0
                    }
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

    /// 運行終了の束帯の高さ（コンソール直上）。
    static func shutdownBandHeight(containerWidth: CGFloat, bandViewportHeight: CGFloat) -> CGFloat {
        let targetW = min(containerWidth * 0.72, 340)
        var ticketH = MarsTicketSpec.height(forWidth: targetW)
        let maxH = max(72, bandViewportHeight - 8)
        ticketH = min(ticketH, maxH)
        return ticketH + 14
    }
}
