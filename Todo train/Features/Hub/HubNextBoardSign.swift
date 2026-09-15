//
//  HubNextBoardSign.swift
//  Todo train
//

import SwiftData
import SwiftUI

struct HubNextBoardSign: View {
    @Environment(SessionManager.self) private var sessionManager
    @Query(sort: \TimetableBlock.startsAt) private var blocks: [TimetableBlock]
    var onOpenBoard: () -> Void

    private var nextLine: (kind: TimetableCopy.Kind, title: String, startsAt: Date)? {
        let now = Date()
        let adopted = blocks
            .filter { $0.isActive && $0.endsAt > now }
            .sorted { $0.startsAt < $1.startsAt }
            .first
        let notice = sessionManager.noticeOccurrences
            .filter { $0.isAdoptable && $0.endsAt > now }
            .sorted { $0.startsAt < $1.startsAt }
            .first
        switch (adopted, notice) {
        case let (adopted?, notice?):
            if adopted.calendarEventIdentifier == notice.eventIdentifier
                || adopted.startsAt <= notice.startsAt {
                return (.board, adopted.title, adopted.startsAt)
            }
            return (.notice, notice.title, notice.startsAt)
        case let (adopted?, nil):
            return (.board, adopted.title, adopted.startsAt)
        case let (nil, notice?):
            return (.notice, notice.title, notice.startsAt)
        case (nil, nil):
            return nil
        }
    }

    var body: some View {
        Button(action: onOpenBoard) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(nextLine?.kind.label ?? TimetableCopy.notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let nextLine {
                    Text(TimetableCopy.clockLine(title: nextLine.title, startsAt: nextLine.startsAt))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text(TimetableCopy.nextNone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, TrainTheme.Space.md)
            .padding(.vertical, 10)
            .background(TrainTheme.surface, in: RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .task { await sessionManager.refreshCalendarBoard() }
        .accessibilityLabel(nextLine?.kind.label ?? TimetableCopy.notice)
        .accessibilityValue(
            nextLine.map {
                TimetableCopy.clockLine(title: $0.title, startsAt: $0.startsAt)
            } ?? TimetableCopy.nextNone
        )
    }
}
