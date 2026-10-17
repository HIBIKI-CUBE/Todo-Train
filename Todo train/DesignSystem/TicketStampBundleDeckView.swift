//
//  TicketStampBundleDeckView.swift
//  Todo train
//
//  きっぷの束 — 扇状に重ね、なぞって一枚ずつめくる。
//

import SwiftUI
import UIKit

enum TicketStampBundleDeckAxis {
    case horizontal
    case verticalHistoryEdge
}

struct TicketStampBundleDeckView: View {
    var stamps: [TicketStampBundleAssembly.Stamp]
    @Binding var focusIndex: Int
    var axis: TicketStampBundleDeckAxis
    var dayBoundaries: Set<Int> = []
    var onSelect: (TicketStampBundleAssembly.Stamp) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var haptics = TicketStampBundleHaptics()
    @State private var selectionPulse = 0
    @State private var boundaryPulse = 0

    private var visibleStamps: [TicketStampBundleAssembly.Stamp] {
        Array(stamps.suffix(from: min(focusIndex, stamps.count)))
    }

    var body: some View {
        Group {
            if stamps.isEmpty {
                emptyPlaceholder
            } else {
                deck
            }
        }
        .onAppear {
            if stamps.isEmpty {
                focusIndex = 0
            } else {
                focusIndex = min(focusIndex, stamps.count - 1)
            }
            haptics.prepare()
        }
        .onChange(of: stamps.count) { _, count in
            focusIndex = min(focusIndex, max(0, count - 1))
        }
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: boundaryPulse)
        .accessibilityElement(children: .contain)
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
    }

    private var emptyPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            .frame(maxWidth: .infinity)
            .frame(height: axis == .horizontal ? 120 : 160)
            .overlay {
                Text("この日は検札した切符がありません")
                    .font(.footnote)
                    .foregroundStyle(FocusPanel.muted)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .accessibilityLabel("この日は検札した切符がありません")
    }

    private var deck: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 24, 360)
            let height = MarsTicketSpec.height(forWidth: width)
            let scale = axis == .horizontal ? min(1, (geo.size.width - 32) / width) : 0.72
            ZStack {
                ForEach(Array(visibleStamps.enumerated()), id: \.element.id) { offset, stamp in
                    let index = focusIndex + offset
                    StampedMarsTicketFace(stamp: stamp, scale: scale)
                        .frame(width: width * scale, height: height * scale)
                        .rotationEffect(
                            .degrees(fanRotation(offset: offset)),
                            anchor: .bottom
                        )
                        .offset(fanOffset(offset: offset, drag: dragOffset))
                        .zIndex(Double(offset))
                        .onTapGesture {
                            onSelect(stamp)
                        }
                        .accessibilityAddTraits(index == focusIndex ? .isSelected : [])
                        .accessibilityAction(named: "詳細") {
                            onSelect(stamp)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(panGesture(in: geo.size))
        }
        .frame(height: axis == .horizontal ? 168 : 200)
    }

    private func fanRotation(offset: Int) -> Double {
        let spread = axis == .horizontal ? 4.5 : 3.0
        return Double(offset) * spread - Double(min(visibleStamps.count - 1, 4)) * spread * 0.35
    }

    private func fanOffset(offset: Int, drag: CGFloat) -> CGSize {
        let step: CGFloat = axis == .horizontal ? 14 : 10
        let primary = CGFloat(offset) * step + drag * 0.35
        if axis == .horizontal {
            return CGSize(width: primary, height: CGFloat(offset) * 3)
        }
        return CGSize(width: CGFloat(offset) * 4, height: primary)
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let delta = axis == .horizontal ? value.translation.width : value.translation.height
                dragOffset = delta
            }
            .onEnded { value in
                let delta = axis == .horizontal ? value.translation.width : value.translation.height
                let velocity = axis == .horizontal ? value.velocity.width : value.velocity.height
                let threshold: CGFloat = axis == .horizontal ? 36 : 28
                var steps = 0
                if abs(velocity) > 900 {
                    steps = velocity > 0 ? -1 : 1
                } else if delta > threshold {
                    steps = -1
                } else if delta < -threshold {
                    steps = 1
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
            if crossedBoundary {
                boundaryPulse += 1
            }
        } else if crossedBoundary {
            boundaryPulse += 1
        } else {
            selectionPulse += 1
        }
    }
}

private final class TicketStampBundleHaptics {
    let selection = UISelectionFeedbackGenerator()
    let impact = UIImpactFeedbackGenerator(style: .medium)

    func prepare() {
        selection.prepare()
        impact.prepare()
    }
}
