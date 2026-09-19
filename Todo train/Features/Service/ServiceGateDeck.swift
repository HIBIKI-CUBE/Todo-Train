//
//  ServiceGateDeck.swift
//  Todo train
//
//  揃えの盤。見せものと今日の事実。進行は ServiceGateSequence。
//

import SwiftData
import SwiftUI

struct ServiceGateDeck: View {
    var reveal: ServiceGateSequence.Reveal
    var dayText: String
    var now: Date
    var occupancyRows: [TimetableOccupancyRow]
    var occupancyMarks: [TimetableOccupancyMark]
    var occupancyActionTitle: String?
    var occupancyAction: (() -> Void)?
    var additionalOccupancyRows: [TimetableOccupancyRow]
    var additionalActionTitle: String?
    var additionalAction: ((UUID) -> Void)?
    var consistTickets: [Ticket]
    var leadTicketID: UUID?
    var calendarAuthorization: CalendarBoardAuthorization
    var onMakeLead: (Ticket) -> Void
    var onMoveConsist: (Ticket, Int) -> Void
    var onRequestCalendar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var occupancyHands: [TimetableOccupancyRow] {
        ServiceGateSequence.occupancyHands(occupancyRows + additionalOccupancyRows)
    }

    private var consistLead: [Ticket] {
        ServiceGateSequence.consistLead(consistTickets)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            FocusControlDivider()
            theatricalLamps
            plaques
            FocusControlDivider()
            clockBand
            FocusControlDivider()
            ScrollView {
                VStack(spacing: 0) {
                    occupancy
                    consist
                    calendarHand
                }
            }
            .scrollIndicators(.hidden)
            .allowsHitTesting(reveal.canInteract)
        }
        .opacity(0.55 + 0.45 * reveal.wash)
        .offset(y: (1 - reveal.edgeLift) * 16)
        .scaleEffect(0.972 + 0.028 * reveal.edgeLift, anchor: .bottom)
        .animation(reduceMotion ? nil : ServiceCabinMotion.rowIn, value: reveal.serviceLit)
        .animation(reduceMotion ? nil : ServiceCabinMotion.rowIn, value: reveal.occupancyLive)
        .animation(reduceMotion ? nil : ServiceCabinMotion.rowIn, value: reveal.consistLive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: reveal.edgeLift)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: TrainTheme.Space.sm) {
            Text(dayText)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(reveal.dateLit ? FocusPanel.ink : FocusPanel.ink.opacity(0.14))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("運行中")
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(reveal.serviceLit ? FocusPanel.ink : FocusPanel.ink.opacity(0.14))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(FocusPanel.fill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reveal.serviceLit ? "運行中 \(dayText)" : "盤")
    }

    private var theatricalLamps: some View {
        HStack(spacing: 6) {
            ForEach(0..<ServiceGateSequence.theatricalLampLimit, id: \.self) { index in
                Capsule()
                    .fill(
                        index < reveal.theatricalLampCount
                            ? Color.white.opacity(0.22)
                            : Color.white.opacity(0.05)
                    )
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var plaques: some View {
        HStack(spacing: 0) {
            plaqueCell("運行", on: reveal.serviceLit)
            FocusControlVerticalDivider()
            plaqueCell("占有", on: reveal.occupancyLive > 0)
            FocusControlVerticalDivider()
            plaqueCell("編成", on: reveal.consistLive > 0)
        }
        .overlay {
            Rectangle()
                .strokeBorder(FocusPanel.hairline, lineWidth: FocusPanel.hairlineWidth)
        }
        .overlay(alignment: .trailing) {
            if let plaque = reveal.plaque {
                Text(plaque)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(FocusPanel.ink.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("運行 占有 編成")
    }

    private func plaqueCell(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .default))
            .foregroundStyle(on ? FocusPanel.ink : FocusPanel.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(on ? FocusPanel.fillRaised : Color.clear)
            .animation(ServiceCabinMotion.lampClick, value: on)
            .accessibilityLabel(title)
            .accessibilityValue(on ? "灯" : "消")
    }

    private var clockBand: some View {
        let salt = Int((reveal.clockProgress * 18).rounded(.down))
        let parts = ServiceGateSequence.rollingClockDigits(
            at: now,
            progress: reveal.clockProgress,
            salt: salt
        )
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.hourMinute)
                Text(":")
                    .font(.system(size: 28, weight: .medium, design: .default))
                    .opacity(reveal.clockProgress >= 1 || reduceMotion ? 1 : 0.35)
                Text(parts.second)
                    .font(.system(size: 28, weight: .medium, design: .default))
            }
            .font(.system(size: 44, weight: .semibold, design: .default))
            .monospacedDigit()
            .foregroundStyle(
                reveal.clockProgress > 0
                    ? FocusPanel.ink.opacity(0.28 + 0.72 * reveal.clockProgress)
                    : FocusPanel.ink.opacity(0.12)
            )
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .frame(maxWidth: .infinity)

            if reveal.tapeLive {
                ServiceCabinTape(
                    lamp: .live,
                    rest: ServiceCabinSequence.tapeRest(marks: occupancyMarks),
                    reduceMotion: reduceMotion
                )
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(Color.black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("時刻")
        .accessibilityValue(reveal.clockProgress >= 1 ? "\(parts.hourMinute):\(parts.second)" : "揃い中")
    }

    @ViewBuilder
    private var occupancy: some View {
        if occupancyHands.isEmpty && reveal.occupancySilhouettes == 0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if reveal.occupancySilhouettes > 0 {
                    ForEach(0..<reveal.occupancySilhouettes, id: \.self) { _ in
                        silhouette(height: 52)
                    }
                }
                ForEach(Array(occupancyHands.prefix(reveal.occupancyLive).enumerated()), id: \.element.id) { _, row in
                    OccupancyDestinationSign(
                        row: row,
                        surface: .cabin,
                        compact: false,
                        actionTitle: reveal.canInteract ? occupancyActionTitle(for: row) : nil,
                        action: reveal.canInteract ? occupancyAction(for: row) : nil
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FocusPanel.fill)
            .accessibilityLabel("占有")
        }
    }

    @ViewBuilder
    private var consist: some View {
        if consistLead.isEmpty && reveal.consistSilhouettes == 0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if reveal.consistSilhouettes > 0 {
                    ForEach(0..<reveal.consistSilhouettes, id: \.self) { _ in
                        silhouette(height: 22)
                    }
                }
                ForEach(Array(consistLead.prefix(reveal.consistLive).enumerated()), id: \.element.id) { index, ticket in
                    consistRow(ticket, index: index)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FocusPanel.fill)
            .accessibilityLabel("編成")
        }
    }

    private func consistRow(_ ticket: Ticket, index: Int) -> some View {
        let isLead = ticket.id == leadTicketID || (leadTicketID == nil && index == 0)
        return HStack(spacing: 10) {
            Button {
                onMakeLead(ticket)
            } label: {
                Circle()
                    .fill(isLead ? FocusPanel.ink : Color.white.opacity(0.14))
                    .frame(width: 9, height: 9)
            }
            .buttonStyle(.plain)
            .disabled(!reveal.canInteract)
            .accessibilityLabel(isLead ? "先頭" : "先頭にする")

            Text(ticket.title)
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundStyle(FocusPanel.ink.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(max(ticket.estimatedSeconds / 60, 1))分")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(FocusPanel.muted)

            if reveal.canInteract {
                VStack(spacing: 2) {
                    Button {
                        onMoveConsist(ticket, -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .disabled(index == 0)
                    Button {
                        onMoveConsist(ticket, 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .disabled(index >= consistLead.count - 1)
                }
                .foregroundStyle(FocusPanel.muted)
                .buttonStyle(.plain)
                .accessibilityLabel("編成の位置")
            }
        }
    }

    @ViewBuilder
    private var calendarHand: some View {
        if calendarAuthorization != .authorized, reveal.canInteract {
            Button(action: onRequestCalendar) {
                Text(calendarAuthorization == .denied ? TimetableCopy.calendarDenied : "掲示を読む")
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundStyle(FocusPanel.ink.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(FocusPanel.fill)
        }
    }

    private func silhouette(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
    }

    private func occupancyActionTitle(for row: TimetableOccupancyRow) -> String? {
        if row.id == occupancyRows.first?.id {
            return occupancyActionTitle
        }
        if additionalOccupancyRows.contains(where: { $0.id == row.id }) {
            return additionalActionTitle
        }
        return nil
    }

    private func occupancyAction(for row: TimetableOccupancyRow) -> (() -> Void)? {
        if row.id == occupancyRows.first?.id {
            return occupancyAction
        }
        if additionalOccupancyRows.contains(where: { $0.id == row.id }) {
            return { additionalAction?(row.id) }
        }
        return nil
    }
}
