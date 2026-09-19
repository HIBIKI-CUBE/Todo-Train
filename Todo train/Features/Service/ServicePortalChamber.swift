//
//  ServicePortalChamber.swift
//  Todo train
//
//  閉じた運転台。光は棚面と文字を照らす。盤は下からせり上がるシートではない。
//

import SwiftUI

struct ServicePortalChamber: View {
    var presence: ServicePortalSequence.Presence
    var roomCharge: Double
    var dayText: String
    var now: Date
    var occupancyRows: [TimetableOccupancyRow]
    var occupancyMarks: [TimetableOccupancyMark]
    var occupancyActionTitle: String?
    var occupancyAction: (() -> Void)?
    var additionalOccupancyRows: [TimetableOccupancyRow]
    var additionalActionTitle: String?
    var additionalAction: ((UUID) -> Void)?
    var consistItems: [ServiceCabinConsistItem]
    var leadTicketID: UUID?
    var calendarAuthorization: CalendarBoardAuthorization
    var onMakeLead: (UUID) -> Void
    var onRequestCalendar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var occupancyHands: [TimetableOccupancyRow] {
        ServicePortalSequence.occupancyHands(occupancyRows + additionalOccupancyRows)
    }

    private var consistLead: [ServiceCabinConsistItem] {
        ServicePortalSequence.consistLead(consistItems)
    }

    private var bloom: Double {
        min(1.55, presence.volumeGlow + roomCharge * 0.90)
    }

    private var emptyMorning: Bool {
        occupancyHands.isEmpty && consistLead.isEmpty
    }

    private var showsPlates: Bool {
        presence.wake >= 0.5
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                volumeLight
                hangingClock(width: geo.size.width, height: geo.size.height)
                shelf
                    .frame(height: geo.size.height * (emptyMorning ? 0.42 : 0.52))
                    .padding(.bottom, 76)
            }
        }
        .scaleEffect(1 - ServicePortalSequence.primeRoomTighten * roomCharge)
        .animation(reduceMotion ? nil : PortalChamberMotion.ignite, value: presence.wake)
        .animation(reduceMotion ? nil : PortalChamberMotion.wash, value: presence.washTravel)
        .animation(reduceMotion ? nil : PortalChamberMotion.seat, value: presence.occupancyLive)
        .animation(reduceMotion ? nil : PortalChamberMotion.seat, value: presence.consistLive)
        .animation(reduceMotion ? nil : PortalChamberMotion.charge, value: roomCharge)
        .accessibilityElement(children: .contain)
    }

    private var volumeLight: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(0.06 * presence.wake + 0.10 * roomCharge),
                    Color.white.opacity(0.22 * bloom + 0.20 * roomCharge)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(0.08 * bloom),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.72),
                startRadius: 8,
                endRadius: 280 + 80 * roomCharge
            )
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.42 + 0.48 * roomCharge)
                ],
                center: .center,
                startRadius: 30 + 10 * (1 - roomCharge),
                endRadius: 420 - 90 * roomCharge
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hangingClock(width: CGFloat, height: CGFloat) -> some View {
        let progress = presence.clockProgress
        let salt = Int((progress * 16).rounded(.down))
        let parts = ServicePortalSequence.rollingClockDigits(
            at: now,
            progress: progress,
            salt: salt
        )
        let lit = 0.18 + 0.82 * progress
        let glow = bloom * max(progress, roomCharge * 0.35)
        let fontSize = min(width * 0.22, emptyMorning ? 64 : 44)
        return VStack {
            Spacer(minLength: height * (emptyMorning ? 0.18 : 0.08))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.hourMinute)
                Text(":")
                    .font(.system(size: fontSize * 0.62, weight: .medium, design: .default))
                    .opacity(progress >= 1 || reduceMotion ? 1 : 0.38)
                Text(parts.second)
                    .font(.system(size: fontSize * 0.62, weight: .medium, design: .default))
            }
            .font(.system(size: fontSize, weight: .semibold, design: .default))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(lit))
            .shadow(color: Color.white.opacity(0.28 + 0.50 * glow), radius: 14 + 12 * glow)
            .opacity(progress > 0.04 ? 1 : 0)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("時刻")
        .accessibilityValue(progress >= 1 ? "\(parts.hourMinute):\(parts.second)" : "揃い中")
    }

    private var shelf: some View {
        ZStack(alignment: .top) {
            shelfBody
            wash
            beadWash
            VStack(alignment: .leading, spacing: 12) {
                lip
                occupancy
                consist
                calendarHand
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .rotation3DEffect(
            .degrees((1 - presence.shelfPitch) * (reduceMotion ? 2 : 6)),
            axis: (1, 0, 0),
            anchor: .bottom,
            perspective: 0.9
        )
        .offset(y: (1 - presence.shelfRise) * (reduceMotion ? 4 : 12))
        .opacity(0.28 + 0.72 * presence.horizon)
    }

    private var shelfBody: some View {
        Rectangle()
            .fill(
                Color.white.opacity(
                    0.035 + 0.16 * presence.wake + 0.22 * roomCharge
                )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.28 + 0.55 * bloom))
                    .frame(height: 2)
                    .shadow(color: Color.white.opacity(0.65 * bloom), radius: 12)
            }
    }

    private var wash: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(0.22 * presence.washTravel + 0.12 * roomCharge),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.48)
            .offset(x: (presence.washTravel * 1.15 - 0.18) * geo.size.width)
            .blur(radius: reduceTransparency ? 0 : 10)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var beadWash: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.16 * bloom + 0.12 * roomCharge),
                Color.white.opacity(0.04 * bloom),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var lip: some View {
        VStack(alignment: .leading, spacing: 8) {
            beads
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("運行中")
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundStyle(
                        Color.white.opacity(presence.serviceLit ? 1 : 0.10 + 0.22 * presence.wake)
                    )
                    .shadow(
                        color: Color.white.opacity(
                            presence.serviceLit ? 0.45 + 0.40 * bloom : 0.12 * presence.wake
                        ),
                        radius: presence.serviceLit ? 14 : 6
                    )
                Spacer(minLength: 8)
                Text(dayText)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(
                        Color.white.opacity(presence.dateLit ? 0.96 : 0.10 + 0.18 * presence.wake)
                    )
                    .shadow(
                        color: presence.dateLit ? Color.white.opacity(0.35 + 0.25 * bloom) : .clear,
                        radius: 8
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presence.serviceLit ? "運行中 \(dayText)" : "盤")
        }
    }

    private var beads: some View {
        HStack(spacing: 8) {
            ForEach(0..<ServicePortalSequence.beadLimit, id: \.self) { index in
                PortalShelfBead(
                    on: index < presence.beadCount,
                    bloom: bloom,
                    reduceTransparency: reduceTransparency
                )
            }
        }
        .overlay(alignment: .leading) {
            if let plaque = presence.plaque {
                Text(plaque)
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.18))
                    .shadow(color: Color.white.opacity(0.45), radius: 6)
                    .offset(y: -18)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var occupancy: some View {
        if showsPlates, !occupancyHands.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if presence.tapeLive {
                    ServiceCabinTape(
                        lamp: .live,
                        rest: ServiceCabinSequence.tapeRest(marks: occupancyMarks),
                        reduceMotion: reduceMotion
                    )
                    .opacity(0.85)
                }
                ForEach(Array(occupancyHands.enumerated()), id: \.element.id) { index, row in
                    let lit = index < presence.occupancyLive
                    OccupancyDestinationSign(
                        row: row,
                        surface: .cabin,
                        compact: occupancyHands.count > 2,
                        actionTitle: lit && presence.canInteract ? occupancyActionTitle(for: row) : nil,
                        action: lit && presence.canInteract ? occupancyAction(for: row) : nil
                    )
                    .opacity(lit ? 1 : 0.16)
                    .scaleEffect(lit ? 1 : 0.94, anchor: .bottom)
                    .shadow(color: Color.white.opacity(lit ? 0.18 * bloom : 0), radius: 8)
                    .allowsHitTesting(lit && presence.canInteract)
                }
            }
            .transition(.identity)
            .accessibilityLabel("占有")
        }
    }

    @ViewBuilder
    private var consist: some View {
        if showsPlates, !consistLead.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(consistLead.enumerated()), id: \.element.id) { index, item in
                    let lit = index < presence.consistLive
                    consistRow(item, index: index)
                        .opacity(lit ? 1 : 0.16)
                        .scaleEffect(lit ? 1 : 0.94, anchor: .bottom)
                        .allowsHitTesting(lit && presence.canInteract)
                }
            }
            .transition(.identity)
            .accessibilityLabel("編成")
        }
    }

    private func consistRow(_ item: ServiceCabinConsistItem, index: Int) -> some View {
        let isLead = item.id == leadTicketID || (leadTicketID == nil && index == 0)
        return Button {
            onMakeLead(item.id)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isLead ? Color.white : Color.white.opacity(0.16))
                    .frame(width: 9, height: 9)
                    .shadow(color: isLead ? Color.white.opacity(0.75) : .clear, radius: 6)
                    .accessibilityLabel(isLead ? "先頭" : "先頭にする")
                Text(item.title)
                    .font(.system(size: 16, weight: .medium, design: .default))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(item.minutes)分")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.58))
            }
        }
        .buttonStyle(.plain)
        .disabled(!presence.canInteract)
    }

    @ViewBuilder
    private var calendarHand: some View {
        if calendarAuthorization != .authorized, presence.canInteract {
            Button(action: onRequestCalendar) {
                Text(calendarAuthorization == .denied ? "カレンダーを読む" : "掲示を読む")
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

private struct PortalShelfBead: View {
    var on: Bool
    var bloom: Double
    var reduceTransparency: Bool

    var body: some View {
        ZStack {
            if on, !reduceTransparency {
                Circle()
                    .fill(Color.white.opacity(0.62 * bloom))
                    .blur(radius: 8)
                    .scaleEffect(x: 2.6, y: 3.4)
            }
            Circle()
                .fill(on ? Color.white.opacity(0.82 + 0.18 * bloom) : Color.white.opacity(0.10))
                .shadow(color: on ? Color.white.opacity(0.8 * bloom) : .clear, radius: on ? 8 : 0)
        }
        .frame(width: 11, height: 11)
        .animation(ServiceCabinMotion.lampClick, value: on)
    }
}

private enum PortalChamberMotion {
    static let ignite = Animation.easeOut(duration: 0.10)
    static let wash = Animation.easeInOut(duration: 0.22)
    static let seat = Animation.spring(response: 0.32, dampingFraction: 0.84)
    static let charge = Animation.easeOut(duration: 0.06)
}
