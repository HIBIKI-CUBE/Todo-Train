//
//  ServicePortalChamber.swift
//  Todo train
//
//  閉じた運転台。光は棚から上がる。盤はリスト待ちではない。
//

import SwiftUI

struct ServicePortalChamber: View {
    var presence: ServicePortalSequence.Presence
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
        min(1.25, presence.volumeGlow + primeProgress * 0.45)
    }

    private var emptyMorning: Bool {
        occupancyHands.isEmpty && consistLead.isEmpty
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
        .scaleEffect(1 - 0.045 * primeProgress)
        .animation(reduceMotion ? nil : PortalChamberMotion.rise, value: presence.shelfRise)
        .animation(reduceMotion ? nil : PortalChamberMotion.wash, value: presence.washTravel)
        .animation(reduceMotion ? nil : PortalChamberMotion.bloom, value: presence.volumeGlow)
        .animation(reduceMotion ? nil : PortalChamberMotion.seat, value: presence.occupancyLive)
        .animation(reduceMotion ? nil : PortalChamberMotion.seat, value: presence.consistLive)
        .animation(reduceMotion ? nil : PortalChamberMotion.charge, value: primeProgress)
        .accessibilityElement(children: .contain)
    }

    private var volumeLight: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(0.04 * presence.wake),
                    Color.white.opacity(0.16 * bloom)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.55 + 0.28 * primeProgress)
                ],
                center: .center,
                startRadius: 40,
                endRadius: 520
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
        let glow = progress * bloom
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
            .foregroundStyle(Color.white.opacity(0.22 + 0.78 * progress))
            .shadow(color: Color.white.opacity(0.40 * glow), radius: 18 * glow)
            .scaleEffect(0.92 + 0.08 * progress)
            .opacity(progress > 0.04 ? 1 : 0)
            .offset(y: (1 - presence.shelfPitch) * 18)
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
            .degrees((1 - presence.shelfPitch) * (reduceMotion ? 4 : 16)),
            axis: (1, 0, 0),
            anchor: .bottom,
            perspective: 0.85
        )
        .offset(y: (1 - presence.shelfRise) * (reduceMotion ? 12 : 72))
        .scaleEffect(0.90 + 0.10 * presence.shelfRise, anchor: .bottom)
        .opacity(0.22 + 0.78 * presence.horizon)
    }

    private var shelfBody: some View {
        Rectangle()
            .fill(Color.white.opacity(0.045 + 0.06 * presence.wake + 0.05 * primeProgress))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.22 + 0.45 * bloom))
                    .frame(height: 2)
                    .shadow(color: Color.white.opacity(0.5 * bloom), radius: 10)
            }
    }

    private var wash: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(0.18 * presence.washTravel),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.42)
            .offset(x: (presence.washTravel * 1.15 - 0.18) * geo.size.width)
            .blur(radius: reduceTransparency ? 0 : 8)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var lip: some View {
        VStack(alignment: .leading, spacing: 8) {
            beads
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("運行中")
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundStyle(Color.white.opacity(presence.serviceLit ? 1 : 0.08))
                    .shadow(
                        color: presence.serviceLit ? Color.white.opacity(0.50 + 0.30 * bloom) : .clear,
                        radius: presence.serviceLit ? 12 : 0
                    )
                Spacer(minLength: 8)
                Text(dayText)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(presence.dateLit ? 0.96 : 0.08))
                    .shadow(color: presence.dateLit ? Color.white.opacity(0.4) : .clear, radius: 8)
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
        if presence.occupancyLive > 0 {
            VStack(alignment: .leading, spacing: 8) {
                if presence.tapeLive {
                    ServiceCabinTape(
                        lamp: .live,
                        rest: ServiceCabinSequence.tapeRest(marks: occupancyMarks),
                        reduceMotion: reduceMotion
                    )
                    .opacity(0.85)
                }
                ForEach(Array(occupancyHands.prefix(presence.occupancyLive).enumerated()), id: \.element.id) { _, row in
                    OccupancyDestinationSign(
                        row: row,
                        surface: .cabin,
                        compact: occupancyHands.count > 2,
                        actionTitle: presence.canInteract ? occupancyActionTitle(for: row) : nil,
                        action: presence.canInteract ? occupancyAction(for: row) : nil
                    )
                    .shadow(color: Color.white.opacity(0.16 * bloom), radius: 8)
                }
            }
            .offset(y: presence.shelfRise >= 0.5 ? 0 : 14)
            .scaleEffect(presence.shelfRise >= 0.5 ? 1 : 0.96, anchor: .bottom)
            .allowsHitTesting(presence.canInteract)
            .accessibilityLabel("占有")
        }
    }

    @ViewBuilder
    private var consist: some View {
        if presence.consistLive > 0 {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(consistLead.prefix(presence.consistLive).enumerated()), id: \.element.id) { index, item in
                    consistRow(item, index: index)
                }
            }
            .offset(y: presence.shelfRise >= 0.6 ? 0 : 12)
            .allowsHitTesting(presence.canInteract)
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
                    .fill(Color.white.opacity(0.55 * bloom))
                    .blur(radius: 7)
                    .scaleEffect(2.2)
            }
            Circle()
                .fill(on ? Color.white.opacity(0.78 + 0.22 * bloom) : Color.white.opacity(0.10))
                .shadow(color: on ? Color.white.opacity(0.75 * bloom) : .clear, radius: on ? 7 : 0)
        }
        .frame(width: 11, height: 11)
        .animation(ServiceCabinMotion.lampClick, value: on)
    }
}

private enum PortalChamberMotion {
    static let rise = Animation.spring(response: 0.58, dampingFraction: 0.78)
    static let wash = Animation.easeInOut(duration: 0.22)
    static let bloom = Animation.easeOut(duration: 0.26)
    static let seat = Animation.spring(response: 0.40, dampingFraction: 0.84)
    static let charge = Animation.easeInOut(duration: 0.07)
}
