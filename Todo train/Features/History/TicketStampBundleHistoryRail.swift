//
//  TicketStampBundleHistoryRail.swift
//  Todo train
//

import SwiftUI

struct TicketStampBundleHistoryRail: View {
    let bundles: [TicketStampBundleAssembly.DayBundle]
    @Binding var selectedDayKey: String
    var onSelectStamp: (TicketStampBundleAssembly.Stamp) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flatIndex: Int = 0
    @State private var deckFocusIndex: Int = 0
    @State private var edgeDrag: CGFloat = 0
    @State private var selectionPulse = 0
    @State private var boundaryPulse = 0

    private var flat: [TicketStampBundleAssembly.FlatStamp] {
        TicketStampBundleAssembly.flatten(bundles)
    }

    private var currentBundle: TicketStampBundleAssembly.DayBundle? {
        guard flat.indices.contains(flatIndex) else { return bundles.first }
        let dayID = flat[flatIndex].stamp.serviceDayID
        return bundles.first { $0.serviceDayID == dayID }
    }

    private var localFocus: Int {
        guard let bundle = currentBundle,
              flat.indices.contains(flatIndex)
        else { return 0 }
        let stampID = flat[flatIndex].stamp.sessionID
        return bundle.stamps.firstIndex { $0.sessionID == stampID } ?? 0
    }

    private var dayBoundaryIndices: Set<Int> {
        Set(flat.enumerated().compactMap { index, item in
            item.dayBoundaryBefore ? index : nil
        })
    }

    var body: some View {
        HStack(spacing: 0) {
            deckColumn
            edgeScrubber
        }
        .onAppear(perform: syncFlatIndexToSelectedDay)
        .onChange(of: selectedDayKey) { _, _ in
            syncFlatIndexToSelectedDay()
        }
        .onChange(of: bundles.count) { _, _ in
            syncFlatIndexToSelectedDay()
        }
        .sensoryFeedback(.selection, trigger: selectionPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: boundaryPulse)
        .accessibilityRotor("運行日") {
            ForEach(bundles) { bundle in
                let label = DayKeyFormatting.displayDay(from: bundle.calendarDayKey)
                AccessibilityRotorEntry(label, textRange: label.startIndex..<label.endIndex) {
                    jumpToBundle(bundle)
                }
            }
        }
    }

    private var deckColumn: some View {
        TicketStampBundleDeckView(
            stamps: currentBundle?.stamps ?? [],
            focusIndex: $deckFocusIndex,
            axis: .verticalHistoryEdge,
            dayBoundaries: [],
            onSelect: onSelectStamp
        )
        .id(currentBundle?.id)
        .onChange(of: flatIndex) { _, _ in
            deckFocusIndex = localFocus
        }
        .onChange(of: currentBundle?.id) { _, _ in
            deckFocusIndex = localFocus
        }
        .onChange(of: deckFocusIndex) { _, local in
            guard let bundle = currentBundle, bundle.stamps.indices.contains(local) else { return }
            let stamp = bundle.stamps[local]
            if let global = flat.firstIndex(where: { $0.stamp.sessionID == stamp.sessionID }) {
                flatIndex = global
            }
        }
        .overlay {
            if let bundle = currentBundle, !bundle.stamps.isEmpty {
                Color.clear
                    .accessibilityLabel("運行日 \(DayKeyFormatting.displayDay(from: bundle.calendarDayKey))")
            }
        }
    }

    private var edgeScrubber: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 22)
            .overlay {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 4, height: 56)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        edgeDrag = value.translation.height
                    }
                    .onEnded { value in
                        let steps = scrubSteps(
                            translation: value.translation.height,
                            velocity: value.velocity.height
                        )
                        applyFlatSteps(steps, fast: abs(value.velocity.height) > 1400)
                        edgeDrag = 0
                    }
            )
            .accessibilityLabel("切符の束")
            .accessibilityHint("上下になぞると、日ごとの束をめくれます")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    applyFlatSteps(1, fast: false)
                case .decrement:
                    applyFlatSteps(-1, fast: false)
                default:
                    break
                }
            }
    }

    private func scrubSteps(translation: CGFloat, velocity: CGFloat) -> Int {
        if abs(velocity) > 1200 {
            return velocity > 0 ? -1 : 1
        }
        let threshold: CGFloat = 40
        if translation > threshold { return -1 }
        if translation < -threshold { return 1 }
        return 0
    }

    private func applyFlatSteps(_ steps: Int, fast: Bool) {
        guard steps != 0, !flat.isEmpty else { return }
        let direction = steps > 0 ? 1 : -1
        for _ in 0..<abs(steps) {
            let next = min(max(0, flatIndex + direction), flat.count - 1)
            guard next != flatIndex else { break }
            let boundary = dayBoundaryIndices.contains(next)
            flatIndex = next
            deckFocusIndex = localFocus
            if let bundle = bundles.first(where: { $0.serviceDayID == flat[next].stamp.serviceDayID }) {
                selectedDayKey = bundle.calendarDayKey
            }
            if fast {
                if boundary { boundaryPulse += 1 }
            } else if boundary {
                boundaryPulse += 1
            } else {
                selectionPulse += 1
            }
        }
    }

    private func jumpToBundle(_ bundle: TicketStampBundleAssembly.DayBundle) {
        guard let index = flat.firstIndex(where: { $0.stamp.serviceDayID == bundle.serviceDayID }) else { return }
        flatIndex = index
        deckFocusIndex = localFocus
        selectedDayKey = bundle.calendarDayKey
        boundaryPulse += 1
    }

    private func syncFlatIndexToSelectedDay() {
        guard let bundle = TicketStampBundleAssembly.bundle(forCalendarDayKey: selectedDayKey, in: bundles) else {
            flatIndex = min(flatIndex, max(0, flat.count - 1))
            deckFocusIndex = localFocus
            return
        }
        if let index = flat.firstIndex(where: { $0.stamp.serviceDayID == bundle.serviceDayID }) {
            flatIndex = index
            deckFocusIndex = localFocus
        }
    }
}
