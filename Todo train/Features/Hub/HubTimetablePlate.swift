//
//  HubTimetablePlate.swift
//  Todo train
//
//  60-minute 案内板 marks: next ダイヤ and the one overlapping now.
//  SA support, not a decision. 発車は止めない。
//

import SwiftUI

struct HubTimetablePlate: View {
    var fit: TimetableFitSnapshot
    var noticeNow: CalendarOccurrence? = nil
    var now: Date
    var width: CGFloat

    var body: some View {
        let marks = plateMarks
        if marks.isEmpty, caption == nil {
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
                }

                if let line = caption {
                    Text(line)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            .frame(width: width, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption ?? TimetableCopy.board)
        }
    }

    private var caption: String? {
        if let current = fit.currentBlock {
            return TimetableCopy.occupyingLine(title: current.title)
        }
        if let noticeNow {
            return TimetableCopy.noticeNowLine(title: noticeNow.title)
        }
        if let next = fit.nextBlock {
            return TimetableFit.nextBlockLine(title: next.title, startsAt: next.startsAt, now: now)
        }
        return nil
    }

    private var plateMarks: [PlateMark] {
        var marks: [PlateMark] = []
        let window = TimeInterval(TimetableFit.markWindowMinutes * 60)
        if let current = fit.currentBlock {
            marks.append(PlateMark(id: current.id, position: 0, isCurrent: true))
        }
        if let next = fit.nextBlock {
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
