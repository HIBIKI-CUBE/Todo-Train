//
//  ServiceGateDeck.swift
//  Todo train
//
//  揃えの盤。診断パネルではなく、光って起き上がる運転台。
//

import SwiftData
import SwiftUI

struct ServiceGateDeck: View {
    var reveal: ServiceGateSequence.Reveal
    var primeProgress: Double
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var occupancyHands: [TimetableOccupancyRow] {
        ServiceGateSequence.occupancyHands(occupancyRows + additionalOccupancyRows)
    }

    private var consistLead: [Ticket] {
        ServiceGateSequence.consistLead(consistTickets)
    }

    private var litBloom: Double {
        min(1.35, reveal.bloom + primeProgress * 0.55)
    }

    private var cabinScale: CGFloat {
        let rise = 0.90 + 0.10 * reveal.rise
        let tighten = 1 - 0.045 * primeProgress
        return rise * tighten
    }

    var body: some View {
        ZStack(alignment: .top) {
            cabinLight
            VStack(alignment: .leading, spacing: 18) {
                identity
                lamps
                if reveal.clockProgress > 0.04 {
                    clockBand
                }
                occupancy
                consist
                calendarHand
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
        }
        .scaleEffect(cabinScale, anchor: .bottom)
        .offset(y: (1 - reveal.rise) * 36)
        .animation(reduceMotion ? nil : ServiceCabinMotion.cabinRise, value: reveal.rise)
        .animation(reduceMotion ? nil : ServiceCabinMotion.bloom, value: reveal.bloom)
        .animation(reduceMotion ? nil : ServiceCabinMotion.rowIn, value: reveal.occupancyLive)
        .animation(reduceMotion ? nil : ServiceCabinMotion.rowIn, value: reveal.consistLive)
        .animation(reduceMotion ? nil : ServiceCabinMotion.primeCharge, value: primeProgress)
        .accessibilityElement(children: .contain)
    }

    private var cabinLight: some View {
        let wash = min(1, reveal.wash + primeProgress * 0.28)
        return ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.22 * litBloom),
                    Color.white.opacity(0.06 * wash),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.72),
                startRadius: 12,
                endRadius: 420
            )
            LinearGradient(
                colors: [
                    Color.white.opacity(reveal.fullLit ? 0.10 : 0.02),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var identity: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(dayText)
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(Color.white.opacity(reveal.dateLit ? 0.96 : 0.08))
                .shadow(color: reveal.dateLit ? Color.white.opacity(0.45) : .clear, radius: 10)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text("運行中")
                .font(.system(size: 22, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(reveal.serviceLit ? 1 : 0.08))
                .shadow(
                    color: reveal.serviceLit ? Color.white.opacity(0.55 + 0.25 * litBloom) : .clear,
                    radius: reveal.serviceLit ? 14 : 0
                )
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reveal.serviceLit ? "運行中 \(dayText)" : "盤")
    }

    private var lamps: some View {
        HStack(spacing: 10) {
            ForEach(0..<ServiceGateSequence.theatricalLampLimit, id: \.self) { index in
                GateGlowLamp(
                    on: index < reveal.theatricalLampCount,
                    bloom: litBloom,
                    reduceTransparency: reduceTransparency
                )
            }
        }
        .overlay(alignment: .leading) {
            if let plaque = reveal.plaque {
                Text(plaque)
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.16))
                    .shadow(color: Color.white.opacity(0.4), radius: 8)
                    .offset(y: -22)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    private var clockBand: some View {
        let salt = Int((reveal.clockProgress * 18).rounded(.down))
        let parts = ServiceGateSequence.rollingClockDigits(
            at: now,
            progress: reveal.clockProgress,
            salt: salt
        )
        let glow = reveal.clockProgress * litBloom
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.hourMinute)
                Text(":")
                    .font(.system(size: 34, weight: .medium, design: .default))
                    .opacity(reveal.clockProgress >= 1 || reduceMotion ? 1 : 0.4)
                Text(parts.second)
                    .font(.system(size: 34, weight: .medium, design: .default))
            }
            .font(.system(size: 56, weight: .semibold, design: .default))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.28 + 0.72 * reveal.clockProgress))
            .shadow(color: Color.white.opacity(0.35 * glow), radius: 16 * glow)
            .minimumScaleFactor(0.4)
            .lineLimit(1)

            if reveal.tapeLive {
                ServiceCabinTape(
                    lamp: .live,
                    rest: ServiceCabinSequence.tapeRest(marks: occupancyMarks),
                    reduceMotion: reduceMotion
                )
                .opacity(0.9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("時刻")
        .accessibilityValue(reveal.clockProgress >= 1 ? "\(parts.hourMinute):\(parts.second)" : "揃い中")
    }

    @ViewBuilder
    private var occupancy: some View {
        if reveal.occupancyLive > 0 {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(occupancyHands.prefix(reveal.occupancyLive).enumerated()), id: \.element.id) { _, row in
                    OccupancyDestinationSign(
                        row: row,
                        surface: .cabin,
                        compact: false,
                        actionTitle: reveal.canInteract ? occupancyActionTitle(for: row) : nil,
                        action: reveal.canInteract ? occupancyAction(for: row) : nil
                    )
                    .shadow(color: Color.white.opacity(0.18 * litBloom), radius: 8)
                }
            }
            .allowsHitTesting(reveal.canInteract)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityLabel("占有")
        }
    }

    @ViewBuilder
    private var consist: some View {
        if reveal.consistLive > 0 {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(consistLead.prefix(reveal.consistLive).enumerated()), id: \.element.id) { index, ticket in
                    consistRow(ticket, index: index)
                }
            }
            .allowsHitTesting(reveal.canInteract)
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
                    .fill(isLead ? Color.white : Color.white.opacity(0.18))
                    .frame(width: 10, height: 10)
                    .shadow(color: isLead ? Color.white.opacity(0.7) : .clear, radius: 6)
            }
            .buttonStyle(.plain)
            .disabled(!reveal.canInteract)
            .accessibilityLabel(isLead ? "先頭" : "先頭にする")

            Text(ticket.title)
                .font(.system(size: 17, weight: .medium, design: .default))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(max(ticket.estimatedSeconds / 60, 1))分")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.62))

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
                .foregroundStyle(Color.white.opacity(0.55))
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
                    .foregroundStyle(Color.white.opacity(0.86))
            }
            .buttonStyle(.plain)
        }
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

struct GateGlowLamp: View {
    var on: Bool
    var bloom: Double
    var reduceTransparency: Bool

    var body: some View {
        ZStack {
            if on, !reduceTransparency {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.55 * bloom))
                    .blur(radius: 8)
                    .scaleEffect(x: 1.35, y: 2.4)
            }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(on ? Color.white.opacity(0.72 + 0.28 * bloom) : Color.white.opacity(0.07))
                .shadow(color: on ? Color.white.opacity(0.7 * bloom) : .clear, radius: on ? 8 : 0)
        }
        .frame(height: 16)
        .animation(ServiceCabinMotion.lampClick, value: on)
    }
}
