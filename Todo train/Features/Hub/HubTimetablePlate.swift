//
//  HubTimetablePlate.swift
//  Todo train
//
//  60-minute 案内板 marks: next ダイヤ and the one overlapping now.
//  SA support, not a decision. 発車は止めない。載せる／外すは確認ではない。
//

import SwiftUI

struct HubTimetablePlate: View {
    var fit: TimetableFitSnapshot
    var noticeNow: CalendarOccurrence? = nil
    var now: Date
    var width: CGFloat
    var onAdoptNotice: (() -> Void)? = nil
    var onUnadoptCurrent: (() -> Void)? = nil

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
                    .accessibilityHidden(true)
                }

                if let line = caption {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
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

    private var dutyTitle: String? {
        if fit.currentBlock != nil, onUnadoptCurrent != nil {
            return TimetableCopy.unadopt
        }
        if fit.currentBlock == nil, noticeNow != nil, onAdoptNotice != nil {
            return TimetableCopy.adopt
        }
        return nil
    }

    private var dutyAction: (() -> Void)? {
        if fit.currentBlock != nil {
            return onUnadoptCurrent
        }
        if noticeNow != nil {
            return onAdoptNotice
        }
        return nil
    }

    private var dutyHint: String {
        if fit.currentBlock != nil {
            return "この枠を今回だけ外す。発車は止めません。"
        }
        return "この掲示を今回だけ載せる。発車は止めません。"
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
