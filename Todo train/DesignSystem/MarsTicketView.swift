//
//  MarsTicketView.swift
//  Todo train
//
//  Unused Mars-style 8.5cm ticket face. Shared by issue, Hub stack, and arrival.
//  No punch / stamp here — those belong to the used overlay.
//

import SwiftUI

struct MarsTicketContent: Equatable {
    var title: String
    var minutes: Int
    var tagNames: [String]
    /// Winning tag chip hex (`sortOrder` min). Nil = untagged cyan stock.
    var colorHex: String?
    var issuedAt: Date
    var serial: String

    init(
        title: String,
        minutes: Int,
        tagNames: [String] = [],
        colorHex: String? = nil,
        issuedAt: Date = .now,
        serial: String? = nil
    ) {
        self.title = title
        self.minutes = max(minutes, 1)
        self.tagNames = tagNames
        self.colorHex = colorHex
        self.issuedAt = issuedAt
        self.serial = serial ?? MarsTicketContent.makeSerial(from: issuedAt)
    }

    init(ticket: Ticket) {
        let tags = ticket.tags.sorted { $0.sortOrder < $1.sortOrder }
        self.init(
            title: ticket.title,
            minutes: max(ticket.estimatedSeconds / 60, 1),
            tagNames: tags.map(\.name),
            colorHex: TicketStockColor.winningColorHex(tags: tags),
            issuedAt: ticket.createdAt,
            serial: MarsTicketContent.makeSerial(from: ticket.createdAt, salt: ticket.id)
        )
    }

    static func makeSerial(from date: Date, salt: UUID? = nil) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        var n = (h * 3600 + m * 60 + s) % 100_000
        if let salt {
            n = (n + abs(salt.uuidString.hashValue % 10_000)) % 100_000
        }
        return String(format: "%05d", n)
    }

    var validityLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return "\(f.string(from: issuedAt))から \(minutes)分間有効"
    }

    var terminalDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy.-M.d"
        return f.string(from: issuedAt)
    }

    var verticalDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M.d"
        return f.string(from: issuedAt)
    }

    var issuedMonth: Int {
        Calendar.current.component(.month, from: issuedAt)
    }

    var issuedDay: Int {
        Calendar.current.component(.day, from: issuedAt)
    }
}

/// Pure unused ticket face. Animation lives in overlays / Hub stack.
struct MarsTicketView: View {
    let content: MarsTicketContent
    var density: MarsTicketSpec.Density = .celebration
    /// 0…1 — title row reveal for thermal scan (1 = fully printed).
    var titleReveal: CGFloat = 1
    /// Hub peek/deck only. Printed occupancy on the 60-minute scale.
    var occupancyMarks: [TimetableOccupancyMark] = []

    private var pad: CGFloat {
        density == .hub ? MarsTicketSpec.hubContentPad : MarsTicketSpec.contentPad
    }

    private var columnSpacing: CGFloat {
        density == .hub ? 4 : 6
    }

    private var stock: TicketStockColor.Stock {
        TicketStockColor.stock(for: content.colorHex)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                paperBackground
                stock.band.color
                    .frame(height: h * 0.34)
                    .frame(maxWidth: .infinity)
                    .offset(y: h * 0.28)

                HStack(alignment: .top, spacing: 0) {
                    faceColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(pad)

                    verticalSerial
                        .frame(width: MarsTicketSpec.verticalSerialWidth)
                        .padding(.vertical, pad)
                        .padding(.trailing, 4)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
                    .strokeBorder(MarsTicketSpec.printInk.opacity(0.18), lineWidth: 0.5)
            )
        }
        .aspectRatio(MarsTicketSpec.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["切符", content.title, "\(content.minutes)分"]
        if !content.tagNames.isEmpty {
            parts.append(content.tagNames.joined(separator: "、"))
        }
        return parts.joined(separator: "。")
    }

    private var paperBackground: some View {
        ZStack {
            stock.paper.color
            MarsTicketGroundPattern()
                .opacity(MarsTicketSpec.groundPatternOpacity)
                .foregroundStyle(MarsTicketSpec.printInk)
        }
    }

    private var faceColumn: some View {
        VStack(alignment: .leading, spacing: columnSpacing) {
            durationTrack

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: columnSpacing) {
                    titleRow

                    if !content.tagNames.isEmpty {
                        viaRow
                    }

                    if density == .celebration {
                        validityRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                fareColumn
            }

            Spacer(minLength: 0)

            footerRow
        }
    }

    private var durationTrack: some View {
        let fill = TicketDurationScale.filled(minutes: content.minutes)
        return ZStack(alignment: .leading) {
            HStack(spacing: MarsTicketSpec.durationTrackGap) {
                ForEach(0..<TicketDurationScale.cellCount, id: \.self) { index in
                    durationCell(amount: TicketDurationScale.cellFillAmount(index: index, fill: fill))
                }
            }
            if density == .hub, !occupancyMarks.isEmpty {
                occupancyPrint(fillMinutes: content.minutes)
            }
        }
        .frame(height: MarsTicketSpec.durationTrackHeight)
        .accessibilityHidden(true)
    }

    private func occupancyPrint(fillMinutes: Int) -> some View {
        let fillFraction = TicketDurationScale.unitFraction(minutes: fillMinutes)
        let ink = MarsTicketSpec.printInk
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(occupancyMarks) { mark in
                    if mark.isCurrent, mark.span > 0 {
                        Rectangle()
                            .fill(ink.opacity(mark.isAdopted ? 0.28 : 0.14))
                            .frame(width: max(4, geo.size.width * mark.span), height: geo.size.height)
                            .offset(x: geo.size.width * mark.position)
                    }
                    if fillFraction > mark.position {
                        Rectangle()
                            .fill(ink.opacity(0.4))
                            .frame(
                                width: max(2, geo.size.width * (min(1, fillFraction) - mark.position)),
                                height: geo.size.height
                            )
                            .offset(x: geo.size.width * mark.position)
                    }
                    occupancyGate(
                        at: mark.isCurrent ? mark.position + mark.span : mark.position,
                        adopted: mark.isAdopted,
                        width: geo.size.width,
                        height: geo.size.height,
                        ink: ink
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func occupancyGate(
        at position: Double,
        adopted: Bool,
        width: CGFloat,
        height: CGFloat,
        ink: Color
    ) -> some View {
        let clamped = min(1, max(0, position))
        RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(ink.opacity(adopted ? 0.95 : 0.48))
            .frame(width: adopted ? 2.2 : 1.6, height: height + 1)
            .offset(x: width * clamped - 1, y: -0.5)
    }

    private func durationCell(amount: Double) -> some View {
        let ink = MarsTicketSpec.printInk
        let shape = RoundedRectangle(cornerRadius: 0.7, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.strokeBorder(ink.opacity(MarsTicketSpec.durationTrackEmptyOpacity), lineWidth: 0.5)
            if amount >= 1 {
                shape.fill(ink)
            } else if amount > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(ink)
                        .frame(width: geo.size.width * amount)
                }
                .clipShape(shape)
            }
        }
    }

    private var viaRow: some View {
        Text(density == .celebration
             ? "経由：" + content.tagNames.joined(separator: "・")
             : content.tagNames.joined(separator: "・"))
            .font(MarsTicketSpec.viaFont())
            .foregroundStyle(MarsTicketSpec.printInk.opacity(density == .hub ? 0.85 : 1))
            .lineLimit(1)
    }

    private var validityRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(content.issuedMonth)月")
            Text("\(content.issuedDay)")
                .font(MarsTicketSpec.validityDayFont())
                .monospacedDigit()
            Text("日から \(content.minutes)分間有効")
        }
        .font(MarsTicketSpec.metaFont())
        .foregroundStyle(MarsTicketSpec.printInk)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var fareColumn: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text("\(content.minutes)")
                .font(MarsTicketSpec.fareFont())
                .monospacedDigit()
                .tracking(-0.6)
            Text("分")
                .font(MarsTicketSpec.fareUnitFont())
        }
        .foregroundStyle(MarsTicketSpec.printInk)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var footerRow: some View {
        Group {
            if density == .celebration {
                Text("Todo train発行  \(content.terminalDate)  \(content.serial)")
                    .font(MarsTicketSpec.terminalFont())
                    .foregroundStyle(MarsTicketSpec.printInk.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
            } else {
                Text(content.terminalDate)
                    .font(MarsTicketSpec.terminalFont())
                    .foregroundStyle(MarsTicketSpec.printInk.opacity(0.75))
                    .monospacedDigit()
            }
        }
    }

    private var titleRow: some View {
        Text(content.title)
            .font(MarsTicketSpec.titleFont())
            .foregroundStyle(MarsTicketSpec.printInk)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .mask(alignment: .top) {
                Rectangle()
                    .scaleEffect(x: 1, y: max(0.001, titleReveal), anchor: .top)
            }
            .opacity(titleReveal <= 0.02 ? 0 : 1)
    }

    private var verticalSerial: some View {
        Text(content.serial + " " + content.verticalDate)
            .font(MarsTicketSpec.serialFont())
            .foregroundStyle(MarsTicketSpec.serialInk)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .rotationEffect(.degrees(90))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// Soft circle lattice — not a JR logo monogram.
private struct MarsTicketGroundPattern: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 14
            let radius: CGFloat = 3.2
            var y: CGFloat = step * 0.5
            var row = 0
            while y < size.height + step {
                var x: CGFloat = row.isMultiple(of: 2) ? step * 0.5 : step
                while x < size.width + step {
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .foreground, lineWidth: 0.6)
                    x += step
                }
                y += step * 0.85
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("短題・祝祭") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        MarsTicketView(
            content: MarsTicketContent(
                title: "メモ",
                minutes: 15,
                tagNames: ["仕事"],
                colorHex: "#0091FF"
            )
        )
        .padding(.horizontal, MarsTicketSpec.horizontalMargin)
    }
}

#Preview("長題・60分") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        MarsTicketView(
            content: MarsTicketContent(
                title: "週次レビューの下書きを共有してコメントを整理する",
                minutes: 60,
                tagNames: ["仕事", "レビュー"],
                colorHex: "#0091FF"
            )
        )
        .padding(.horizontal, MarsTicketSpec.horizontalMargin)
    }
}

#Preview("Hub密度") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        VStack(spacing: 16) {
            MarsTicketView(
                content: MarsTicketContent(
                    title: "週次レビューの下書き",
                    minutes: 25,
                    tagNames: ["仕事"],
                    colorHex: "#0091FF"
                ),
                density: .hub
            )
            MarsTicketView(
                content: MarsTicketContent(
                    title: "買い物",
                    minutes: 5,
                    tagNames: ["生活"],
                    colorHex: "#30A46C"
                ),
                density: .hub
            )
            MarsTicketView(
                content: MarsTicketContent(title: "無題の掃き出し", minutes: 20),
                density: .hub
            )
        }
        .padding(.horizontal, MarsTicketSpec.HubStack.horizontalInset)
    }
}
