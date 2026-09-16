//
//  HubTimetablePlate.swift
//  Todo train
//
//  60-minute 案内板: occupancy rail + clock/remaining. 発車は止めない。
//

import SwiftUI

struct HubTimetablePlate: View {
    var fit: TimetableFitSnapshot
    var now: Date
    var calendar: Calendar = .autoupdatingCurrent
    var width: CGFloat
    var onAdoptNotice: (() -> Void)? = nil
    var onUnadoptCurrent: (() -> Void)? = nil

    var body: some View {
        let rows = TimetableFit.occupancyRows(fit: fit, now: now, calendar: calendar)
        let marks = TimetableFit.occupancyMarks(fit: fit, now: now)
        if rows.isEmpty, marks.isEmpty {
            EmptyView()
        } else {
            TimetableOccupancyMeter(
                rows: rows,
                marks: marks,
                chrome: .inverted
            ) {
                if let dutyTitle, let dutyAction {
                    Button(dutyTitle, action: dutyAction)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TrainTheme.rail)
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .accessibilityHint(TimetableCopy.thisTime)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private var dutyTitle: String? {
        if fit.currentOccupancy?.isAdopted == true, onUnadoptCurrent != nil {
            return TimetableCopy.unadopt
        }
        if fit.currentOccupancy?.isAdopted == false, onAdoptNotice != nil {
            return TimetableCopy.adopt
        }
        return nil
    }

    private var dutyAction: (() -> Void)? {
        if fit.currentOccupancy?.isAdopted == true {
            return onUnadoptCurrent
        }
        if fit.currentOccupancy?.isAdopted == false {
            return onAdoptNotice
        }
        return nil
    }
}
