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
    var issuedAt: Date
    var serial: String

    init(
        title: String,
        minutes: Int,
        tagNames: [String] = [],
        issuedAt: Date = .now,
        serial: String? = nil
    ) {
        self.title = title
        self.minutes = max(minutes, 1)
        self.tagNames = tagNames
        self.issuedAt = issuedAt
        self.serial = serial ?? MarsTicketContent.makeSerial(from: issuedAt)
    }

    init(ticket: Ticket) {
        let tags = ticket.tags.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
        self.init(
            title: ticket.title,
            minutes: max(ticket.estimatedSeconds / 60, 1),
            tagNames: tags,
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
}

/// Pure unused ticket face. Animation lives in overlays / Hub stack.
struct MarsTicketView: View {
    let content: MarsTicketContent
    var density: MarsTicketSpec.Density = .celebration
    /// 0…1 — title row reveal for thermal scan (1 = fully printed).
    var titleReveal: CGFloat = 1

    private var pad: CGFloat {
        density == .hub ? MarsTicketSpec.hubContentPad : MarsTicketSpec.contentPad
    }

    private var columnSpacing: CGFloat {
        density == .hub ? 4 : 6
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                paperBackground
                MarsTicketSpec.paperBand
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
            MarsTicketSpec.paper
            MarsTicketGroundPattern()
                .opacity(MarsTicketSpec.groundPatternOpacity)
                .foregroundStyle(MarsTicketSpec.printInk)
        }
    }

    private var faceColumn: some View {
        VStack(alignment: .leading, spacing: columnSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("切符")
                    .font(MarsTicketSpec.kindFont())
                    .foregroundStyle(MarsTicketSpec.printInk)
                    .tracking(2)
                Spacer(minLength: 4)
                Text("\(content.minutes)分")
                    .font(MarsTicketSpec.metaFont().weight(.bold))
                    .foregroundStyle(MarsTicketSpec.printInk)
                    .monospacedDigit()
            }

            titleRow
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, density == .hub ? 2 : 4)

            if density == .celebration {
                if !content.tagNames.isEmpty {
                    Text("経由：" + content.tagNames.joined(separator: "・"))
                        .font(MarsTicketSpec.viaFont())
                        .foregroundStyle(MarsTicketSpec.printInk)
                        .lineLimit(1)
                }

                Text(content.validityLine)
                    .font(MarsTicketSpec.metaFont())
                    .foregroundStyle(MarsTicketSpec.printInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Text("Todo train発行  \(content.terminalDate)  \(content.serial)")
                    .font(MarsTicketSpec.terminalFont())
                    .foregroundStyle(MarsTicketSpec.printInk.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
            } else {
                if !content.tagNames.isEmpty {
                    Text(content.tagNames.joined(separator: "・"))
                        .font(MarsTicketSpec.viaFont())
                        .foregroundStyle(MarsTicketSpec.printInk.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(content.terminalDate)
                    .font(MarsTicketSpec.terminalFont())
                    .foregroundStyle(MarsTicketSpec.printInk.opacity(0.75))
                    .monospacedDigit()
            }
        }
    }

    private var titleRow: some View {
        Text(content.title)
            .font(density == .hub ? MarsTicketSpec.titleFont().weight(.bold) : MarsTicketSpec.titleFont())
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

#Preview("短題・明") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        MarsTicketView(
            content: MarsTicketContent(title: "メモ", minutes: 15, tagNames: ["仕事"])
        )
        .padding(.horizontal, MarsTicketSpec.horizontalMargin)
    }
}

#Preview("Hub密度") {
    ZStack {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        MarsTicketView(
            content: MarsTicketContent(title: "週次レビューの下書き", minutes: 25, tagNames: ["仕事"]),
            density: .hub
        )
        .padding(.horizontal, MarsTicketSpec.HubStack.horizontalInset)
    }
}
