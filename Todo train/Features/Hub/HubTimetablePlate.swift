//
//  HubTimetablePlate.swift
//  Todo train
//
//  60-minute 案内板 marks: now + next occupancy (ダイヤ and 掲示).
//  SA support, not a decision. 発車は止めない。載せる／外すは確認ではない。
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
        plate(now: now)
    }

    @ViewBuilder
    private func plate(now: Date) -> some View {
        let marks = plateMarks(now: now)
        let lines = TimetableFit.occupancyLines(fit: fit, now: now, calendar: calendar)
        if marks.isEmpty, lines.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if !marks.isEmpty {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.55))
                        Rectangle()
                            .fill(TrainTheme.signalRed)
                            .frame(width: 2)
                            .padding(.leading, 8)
                        ForEach(marks) { mark in
                            Circle()
                                .fill(mark.isCurrent ? TrainTheme.signalAmber : TrainTheme.rail)
                                .frame(width: 7, height: 7)
                                .offset(x: 8 + (width - 24) * mark.position)
                        }
                    }
                    .frame(width: width, height: 16)
                    .accessibilityHidden(true)
                }

                if !lines.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let dutyTitle, let dutyAction {
                            Button(dutyTitle, action: dutyAction)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(TrainTheme.rail)
                                .buttonStyle(.plain)
                                .padding(.vertical, 8)
                                .accessibilityHint(dutyHint)
                        }
                    }
                    .frame(width: width, alignment: .leading)
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

    private var dutyHint: String {
        TimetableCopy.thisTime
    }

    private func plateMarks(now: Date) -> [PlateMark] {
        var marks: [PlateMark] = []
        let window = TimeInterval(TimetableFit.markWindowMinutes * 60)
        if let current = fit.currentOccupancy, current.startsAt <= now {
            marks.append(PlateMark(id: current.id, position: 0, isCurrent: true))
        }
        if let next = fit.nextOccupancy {
            let offset = next.startsAt.timeIntervalSince(now)
            if offset >= 0, offset <= window {
                marks.append(
                    PlateMark(
                        id: next.id,
                        position: max(0, min(1, offset / window)),
                        isCurrent: false
                    )
                )
            }
        }
        return marks
    }
}

private struct PlateMark: Identifiable {
    var id: UUID
    var position: CGFloat
    var isCurrent: Bool
}
