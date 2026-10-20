//
//  TicketStampBundleViewer.swift
//  Todo train
//

import SwiftUI

struct TicketStampBundleViewer: View {
    let bundles: [TicketStampBundleAssembly.DayBundle]
    let initialDayKey: String
    var initialFlatIndex: Int?
    var pinnedFocusUnit: CGFloat? = nil
    var pinnedSpread: CGFloat? = nil
    var onSelectStamp: (TicketStampBundleAssembly.Stamp) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flatIndex: Int = 0
    @State private var deckFocusIndex: Int = 0
    @State private var selectionPulse = 0
    @State private var boundaryPulse = 0
    @State private var deckVerticalLocked = false

    private var flat: [TicketStampBundleAssembly.FlatStamp] {
        TicketStampBundleAssembly.flatten(bundles)
    }

    private var dayBoundaryIndices: Set<Int> {
        Set(flat.enumerated().compactMap { index, item in
            item.dayBoundaryBefore ? index : nil
        })
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

    private var dayTitle: String {
        guard let bundle = currentBundle else { return "" }
        return DayKeyFormatting.displayDay(from: bundle.calendarDayKey)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .trailing) {
                VStack(spacing: TrainTheme.Space.md) {
                    Text(dayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, TrainTheme.Space.sm)
                    Color.clear
                }

                if let bundle = currentBundle {
                    TicketStampBundleDeckView(
                        stamps: bundle.stamps,
                        focusIndex: $deckFocusIndex,
                        style: .viewer,
                        dayBoundaries: dayBoundaryIndicesForLocalFocus(),
                        onSelect: onSelectStamp,
                        verticalGesturesLocked: $deckVerticalLocked,
                        pinnedSpread: pinnedSpread,
                        pinnedFocusUnit: pinnedFocusUnit
                    )
                    .ignoresSafeArea()
                }

                edgeScrubber
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TrainTheme.platform)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard !deckVerticalLocked else { return }
                        guard value.translation.height > 72,
                              abs(value.translation.height) > abs(value.translation.width)
                        else { return }
                        dismiss()
                    }
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onAppear(perform: syncFlatIndexToInitialDay)
        .onChange(of: flatIndex) { _, _ in
            deckFocusIndex = localFocus
        }
        .onChange(of: deckFocusIndex) { _, local in
            guard let bundle = currentBundle, bundle.stamps.indices.contains(local) else { return }
            let stamp = bundle.stamps[local]
            if let global = flat.firstIndex(where: { $0.stamp.sessionID == stamp.sessionID }) {
                flatIndex = global
            }
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

    private var edgeScrubber: some View {
        Color.clear
            .frame(width: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onEnded { value in
                        guard !deckVerticalLocked else { return }
                        let steps = scrubSteps(
                            translation: value.translation.height,
                            velocity: value.velocity.height
                        )
                        applyFlatSteps(steps, fast: abs(value.velocity.height) > 1400)
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

    private func dayBoundaryIndicesForLocalFocus() -> Set<Int> {
        guard let bundle = currentBundle else { return [] }
        var set: Set<Int> = []
        for (index, stamp) in bundle.stamps.enumerated() {
            if let global = flat.firstIndex(where: { $0.stamp.sessionID == stamp.sessionID }),
               dayBoundaryIndices.contains(global) {
                set.insert(index)
            }
        }
        return set
    }

    private func scrubSteps(translation: CGFloat, velocity: CGFloat) -> Int {
        TicketStampBundleGesture.steps(
            translation: Double(translation),
            velocity: Double(velocity),
            threshold: 40,
            flickVelocity: 1200
        )
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
        boundaryPulse += 1
    }

    private func syncFlatIndexToInitialDay() {
        if let forced = initialFlatIndex {
            if flat.indices.contains(forced) {
                flatIndex = forced
                deckFocusIndex = localFocus
                return
            }
            if forced >= flat.count, !flat.isEmpty {
                flatIndex = flat.count - 1
                deckFocusIndex = localFocus
                return
            }
        }
        guard let bundle = TicketStampBundleAssembly.bundle(forCalendarDayKey: initialDayKey, in: bundles),
              let index = flat.firstIndex(where: { $0.stamp.serviceDayID == bundle.serviceDayID })
        else {
            flatIndex = min(flatIndex, max(0, flat.count - 1))
            deckFocusIndex = localFocus
            return
        }
        flatIndex = index
        deckFocusIndex = localFocus
    }
}
