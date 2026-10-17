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

    /// `focusIndex` = いま手前の切符（古い方から数える）。
    private var visibleStamps: [TicketStampBundleAssembly.Stamp] {
        let end = min(focusIndex + 1, stamps.count)
        guard end > 0 else { return [] }
        return Array(stamps.prefix(end))
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
            ZStack {
                ForEach(Array(visibleStamps.enumerated()), id: \.element.id) { offset, stamp in
                    let depth = visibleStamps.count - 1 - offset
                    let isFront = depth == 0
                    StampedMarsTicketFace(stamp: stamp, scale: metrics.scale, showsLogLines: style != .historyStrip)
                        .frame(width: metrics.ticketWidth, height: metrics.ticketHeight)
                        .rotationEffect(
                            .degrees(fanRotation(depth: depth, metrics: metrics)),
                            anchor: .bottom
                        )
                        .offset(fanOffset(depth: depth, drag: dragOffset, metrics: metrics))
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(style == .historyStrip ? nil : panGesture(in: geo.size, metrics: metrics))
        }
        .frame(height: bandHeight)
        .clipped()
    }

    private var bandHeight: CGFloat {
        switch style {
        case .shutdown: 124
        case .historyStrip: 120
        case .viewer: 280
        }
    }

    private struct LayoutMetrics {
        var ticketWidth: CGFloat
        var ticketHeight: CGFloat
        var scale: CGFloat
        var fanStep: CGFloat
        var fanSpread: Double
        var maxFanCards: Int
    }

    private func layoutMetrics(in size: CGSize) -> LayoutMetrics {
        let baseWidth: CGFloat = 300
        let baseHeight = MarsTicketSpec.height(forWidth: baseWidth)
        let visibleCount = min(visibleStamps.count, style == .shutdown ? 5 : 3)
        switch style {
        case .shutdown:
            let pad: CGFloat = 24
            let maxW = max(80, size.width - pad)
            let maxH = max(60, size.height - 8)
            var scale = min(maxW / baseWidth, maxH / baseHeight, 1)
            var fanStep: CGFloat = 9
            let ticketW = baseWidth * scale
            let fanExtent = ticketW + CGFloat(max(0, visibleCount - 1)) * fanStep * scale
            if fanExtent > maxW {
                let squeeze = maxW / fanExtent
                scale *= squeeze
                fanStep *= squeeze
            }
            return LayoutMetrics(
                ticketWidth: baseWidth * scale,
                ticketHeight: baseHeight * scale,
                scale: scale,
                fanStep: fanStep,
                fanSpread: 2.0,
                maxFanCards: 4
            )
        case .historyStrip:
            let maxW = max(60, size.width - 24)
            let maxH = max(50, size.height - 8)
            let scale = min(maxW / baseWidth, maxH / baseHeight, 0.38)
            return LayoutMetrics(
                ticketWidth: baseWidth * scale,
                ticketHeight: baseHeight * scale,
                scale: scale,
                fanStep: 5,
                fanSpread: 1.4,
                maxFanCards: 3
            )
        case .viewer:
            let targetW = size.width * 0.8
            let scale = min(targetW / baseWidth, 1)
            return LayoutMetrics(
                ticketWidth: baseWidth * scale,
                ticketHeight: baseHeight * scale,
                scale: scale,
                fanStep: 12,
                fanSpread: 3.0,
                maxFanCards: 5
            )
        }
    }

    private func fanRotation(depth: Int, metrics: LayoutMetrics) -> Double {
        let capped = min(depth, metrics.maxFanCards)
        return -Double(capped) * metrics.fanSpread
    }

    private func fanOffset(depth: Int, drag: CGFloat, metrics: LayoutMetrics) -> CGSize {
        let capped = min(depth, metrics.maxFanCards)
        let primary = -CGFloat(capped) * metrics.fanStep + drag * 0.28
        return CGSize(width: primary, height: CGFloat(capped) * 2)
    }

    /// 扇の左寄りを補正して、手前の切符を帯の中央に寄せる。
    private func fanCenterNudge(metrics: LayoutMetrics) -> CGFloat {
        guard style == .shutdown || style == .viewer else { return 0 }
        let depth = min(max(0, visibleStamps.count - 1), metrics.maxFanCards)
        return CGFloat(depth) * metrics.fanStep * 0.5
    }

    private func panGesture(in size: CGSize, metrics: LayoutMetrics) -> some Gesture {
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
                } else                 if delta > threshold {
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
}
