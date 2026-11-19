//
//  RunStatusColumn.swift
//  Todo train
//
//  運転状況の列。時間割と同じ時間軸。赤は使わない。
//

import SwiftUI

enum RunStatusColumnLayout {
    static func name(for kind: RunStatusKind, height: CGFloat) -> String? {
        switch nameLength(height: height) {
        case .long:
            return longName(kind)
        case .short:
            return shortName(kind)
        case .hidden:
            return nil
        }
    }

    static func longName(_ kind: RunStatusKind) -> String {
        switch kind {
        case .normal:
            return "平常運転"
        case .dense:
            return "ダイヤ過密"
        case .hold:
            return "見合わせ"
        }
    }

    static func shortName(_ kind: RunStatusKind) -> String {
        switch kind {
        case .normal:
            return "平常"
        case .dense:
            return "過密"
        case .hold:
            return "見合せ"
        }
    }

    static func nameLength(height: CGFloat) -> NameLength {
        if height >= 24 { return .long }
        if height >= 13 { return .short }
        return .hidden
    }

    enum NameLength: Equatable {
        case long
        case short
        case hidden
    }
}

/// 時間割の範囲を、タスクに使える時間かどうかで塗る列。
struct RunStatusColumn: View {
    var bands: [RunStatusBand]
    var range: TimetableRange
    var now: Date
    var reading: RunStatusNow
    var calendar: Calendar = .current

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                hourLines(height: height, width: width)
                ForEach(bands) { band in
                    let top = TimetableColumnLayout.y(of: band.startsAt, range: range, height: height)
                    let bottom = TimetableColumnLayout.y(of: band.endsAt, range: range, height: height)
                    let full = max(1, bottom - top)
                    let visual = max(1, full - 1)
                    bandCell(band, height: full)
                        .frame(width: width, height: visual)
                        .position(x: width / 2, y: top + visual / 2)
                }
            }
            .frame(width: width, height: height)
        }
        .accessibilityElement(children: .contain)
    }

    private func hourLines(height: CGFloat, width: CGFloat) -> some View {
        let marks = TimetableColumnLayout.hourMarks(range: range, height: height, calendar: calendar)
        let interior = marks.dropFirst().dropLast()
        return ZStack(alignment: .topLeading) {
            ForEach(Array(interior), id: \.hour) { mark in
                Rectangle()
                    .fill(OpeningPanelTokens.TimetableChrome.hourLine.opacity(0.6))
                    .frame(width: width, height: 1)
                    .position(x: width / 2, y: mark.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bandCell(_ band: RunStatusBand, height: CGFloat) -> some View {
        let referenced = band.isReferenced(by: reading)
        return ZStack {
            if !referenced {
                face(band.kind)
            }
            if let name = RunStatusColumnLayout.name(for: band.kind, height: height) {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(nameColor(band.kind))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
                    .background {
                        if band.kind == .dense && !referenced {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(OpeningPanelTokens.Palette.window)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .runStatusReferencedBandHighlight(band: band, now: now, reading: reading)
        .overlay {
            if isCurrent(band) && !referenced {
                Rectangle()
                    .strokeBorder(OpeningPanelTokens.RunStatusChrome.brightBandStroke, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RunStatusColumnLayout.longName(band.kind))
    }

    @ViewBuilder
    private func face(_ kind: RunStatusKind) -> some View {
        switch kind {
        case .normal:
            OpeningPanelTokens.TimetableChrome.normalFace
        case .dense:
            ZStack {
                OpeningPanelTokens.TimetableChrome.denseFace
                RunStatusDenseHatch()
            }
        case .hold:
            OpeningPanelTokens.RunStatusChrome.holdFace
                .overlay {
                    Rectangle()
                        .strokeBorder(OpeningPanelTokens.RunStatusChrome.holdEdge, lineWidth: 1)
                }
        }
    }

    private func nameColor(_ kind: RunStatusKind) -> Color {
        switch kind {
        case .normal:
            return OpeningPanelTokens.TimetableChrome.amberSolid
        case .dense:
            return OpeningPanelTokens.TimetableChrome.denseName
        case .hold:
            return OpeningPanelTokens.TimetableChrome.holdName
        }
    }

    private func isCurrent(_ band: RunStatusBand) -> Bool {
        band.startsAt <= now && now < band.endsAt
    }
}

private struct RunStatusDenseHatch: View {
    var body: some View {
        Canvas { context, size in
            var x = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(
                    path,
                    with: .color(OpeningPanelTokens.TimetableChrome.denseHatch),
                    lineWidth: 2
                )
                x += 5
            }
        }
        .allowsHitTesting(false)
    }
}
