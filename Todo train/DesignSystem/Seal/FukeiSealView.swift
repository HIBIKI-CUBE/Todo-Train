//
//  FukeiSealView.swift
//  Todo train
//
//  寸法は FukeiSealLayout、かすれは SealWear。ここでは計算し直さない。
//

import SwiftUI
import TodoTrainSync

struct FukeiSealInput {
    var luxury: Double
    var season: PunctualityJudgment.StampSeason
    var timeOfDay: PunctualityJudgment.StampTimeOfDay
    var seed: UInt64
    var dateText: String
    var detail: SealDetail
}

struct FukeiSealView: View {
    var input: FukeiSealInput

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            guard side > 0 else { return }
            var context = context
            context.translateBy(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2
            )
            draw(in: &context, side: side)
        }
        .compositingGroup()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func draw(in context: inout GraphicsContext, side: CGFloat) {
        let metrics = FukeiSealLayout.metrics(luxury: input.luxury)
        let ink = inkColor(metrics)
        let frame = frameRect(metrics: metrics, side: side)
        let contentInset = CGFloat(metrics.inset) * side
        let content = frame.insetBy(dx: contentInset, dy: contentInset)
        let band = CGRect(
            x: content.minX,
            y: content.minY,
            width: content.width,
            height: CGFloat(metrics.pictureHeight) * side
        )

        strokeFrame(metrics: metrics, frame: frame, contentInset: contentInset, side: side, color: ink, context: &context)

        if input.detail == .compact {
            if metrics.pictureHeight > 0, band.width > 0, band.height > 0 {
                context.fill(Path(band), with: .color(ink))
            }
        } else {
            drawPicture(metrics: metrics, band: band, side: side, color: ink, context: &context)
            drawSeasonMark(metrics: metrics, content: content, frame: frame, side: side, color: ink, context: &context)
        }

        drawWords(metrics: metrics, frame: frame, content: content, side: side, color: ink, context: &context)
        drawWear(metrics: metrics, frame: frame, side: side, context: &context)
    }

    private func inkColor(_ metrics: FukeiSealMetrics) -> Color {
        let mix = metrics.inkMix
        let red = 0.78 + (0.86 - 0.78) * mix
        let green = 0.18 + (0.45 - 0.18) * mix
        let blue = 0.14 + (0.40 - 0.14) * mix
        return Color(red: red, green: green, blue: blue, opacity: metrics.inkOpacity)
    }

    private func frameRect(metrics: FukeiSealMetrics, side: CGFloat) -> CGRect {
        let origin = (1 - CGFloat(metrics.frameSide)) / 2 * side
        let length = CGFloat(metrics.frameSide) * side
        return CGRect(x: origin, y: origin, width: length, height: length)
    }

    private func strokeFrame(
        metrics: FukeiSealMetrics,
        frame: CGRect,
        contentInset: CGFloat,
        side: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        let outer = strokeWidth(metrics.outerStroke, floor: metrics.lineWidthFloor, side: side)
        guard outer > 0 else { return }
        context.stroke(
            Path(frame),
            with: .color(color),
            style: StrokeStyle(lineWidth: outer, lineJoin: .miter)
        )
        guard metrics.innerStroke > 0 else { return }
        let inner = strokeWidth(metrics.innerStroke, floor: metrics.lineWidthFloor, side: side)
        let room = contentInset - outer / 2
        guard room > inner / 2 else { return }
        let centerInset = outer / 2 + room / 2
        let innerRect = frame.insetBy(dx: centerInset, dy: centerInset)
        guard innerRect.width > inner, innerRect.height > inner else { return }
        context.stroke(
            Path(innerRect),
            with: .color(color),
            style: StrokeStyle(lineWidth: inner, lineJoin: .miter)
        )
    }

    /// シーンの枠の高さは 0.60 × innerHeight。下端を絵の帯の下端に合わせ、帯で切る。
    private func drawPicture(
        metrics: FukeiSealMetrics,
        band: CGRect,
        side: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        guard metrics.showsPicture, band.width > 0, band.height > 0 else { return }
        let sceneHeight = CGFloat(0.60 * metrics.innerHeight) * side
        guard sceneHeight > 0 else { return }
        let scene = CGRect(
            x: band.minX,
            y: band.maxY - sceneHeight,
            width: band.width,
            height: sceneHeight
        )
        let line = CGFloat(max(metrics.lineWidthFloor, 0.016)) * side
        context.drawLayer { layer in
            layer.clip(to: Path(band))
            paint(FukeiSealArt.scene(season: input.season, in: scene), color: color, lineWidth: line, context: &layer)
            paint(FukeiSealArt.rails(in: scene), color: color, lineWidth: line, context: &layer)
            if metrics.showsSkyGlyph {
                let glyph = CGFloat(metrics.skyGlyphSize) * side
                let center = CGPoint(x: band.midX, y: band.minY + band.height * 0.40)
                let sky = CGRect(x: center.x - glyph / 2, y: center.y - glyph / 2, width: glyph, height: glyph)
                paint(FukeiSealArt.sky(timeOfDay: input.timeOfDay, in: sky), color: color, lineWidth: line, context: &layer)
            }
        }
    }

    private func drawSeasonMark(
        metrics: FukeiSealMetrics,
        content: CGRect,
        frame: CGRect,
        side: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        guard metrics.seasonMarkAlpha > 0, content.width > 0 else { return }
        let titleTop = frame.minY + CGFloat(metrics.textBlockTop) * side
        let gap = titleTop - content.minY
        guard gap > 1 else { return }
        let markSide = min(content.width * 0.62, gap * 0.88)
        guard markSide > 1 else { return }
        let mark = CGRect(
            x: content.midX - markSide / 2,
            y: content.minY + (gap - markSide) / 2,
            width: markSide,
            height: markSide
        )
        let saved = context.opacity
        context.opacity = saved * metrics.seasonMarkAlpha
        let line = CGFloat(max(metrics.lineWidthFloor, 0.016)) * side
        paint(FukeiSealArt.seasonMark(season: input.season, in: mark), color: color, lineWidth: line, context: &context)
        context.opacity = saved
    }

    private func drawWords(
        metrics: FukeiSealMetrics,
        frame: CGRect,
        content: CGRect,
        side: CGFloat,
        color: Color,
        context: inout GraphicsContext
    ) {
        let titleHeight = CGFloat(metrics.titleSize) * side
        guard titleHeight > 0, content.width > 0 else { return }
        let titleTop: CGFloat
        if input.detail == .compact {
            if metrics.pictureHeight > 0 {
                titleTop = frame.minY + CGFloat(metrics.inset + metrics.pictureHeight + 0.03) * side
            } else {
                titleTop = content.midY - titleHeight / 2
            }
        } else {
            titleTop = frame.minY + CGFloat(metrics.textBlockTop) * side
        }
        let title = CGRect(x: content.minX, y: titleTop, width: content.width, height: titleHeight)
        FukeiSealGlyphs.draw(text: "定時", in: title, context: &context, color: color)

        guard input.detail == .full else { return }
        let dateHeight = CGFloat(metrics.dateSize) * side
        let date = CGRect(
            x: content.minX,
            y: title.maxY + 0.02 * side,
            width: content.width,
            height: dateHeight
        )
        FukeiSealGlyphs.draw(text: input.dateText, in: date, context: &context, color: color)
    }

    private func drawWear(
        metrics: FukeiSealMetrics,
        frame: CGRect,
        side: CGFloat,
        context: inout GraphicsContext
    ) {
        let wear = SealWear.make(seed: input.seed, luxury: input.luxury, detail: input.detail)
        context.blendMode = .destinationOut
        for speck in wear.specks {
            let radius = CGFloat(speck.radius) * side
            guard radius > 0 else { continue }
            let rect = CGRect(
                x: CGFloat(speck.x) * side - radius,
                y: CGFloat(speck.y) * side - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.white))
        }
        for chip in wear.chips {
            let dx = CGFloat(cos(chip.angle))
            let dy = CGFloat(sin(chip.angle))
            let reach = 0.5 / max(abs(dx), abs(dy), 0.0001)
            let center = CGPoint(
                x: frame.midX + dx * reach * frame.width,
                y: frame.midY + dy * reach * frame.height
            )
            let chipSide = CGFloat(chip.size) * side
            let rect = CGRect(
                x: center.x - chipSide / 2,
                y: center.y - chipSide / 2,
                width: chipSide,
                height: chipSide
            )
            context.fill(Path(ellipseIn: rect), with: .color(.white))
        }
        let depth = wear.pressureDepth
        guard depth > 0 else { return }
        let dx = CGFloat(cos(wear.pressureAngle))
        let dy = CGFloat(sin(wear.pressureAngle))
        let center = CGPoint(x: side / 2, y: side / 2)
        let half = side / 2
        context.fill(
            Path(CGRect(x: 0, y: 0, width: side, height: side)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0), location: 0),
                    .init(color: Color.white.opacity(depth), location: 1),
                ]),
                startPoint: CGPoint(x: center.x - dx * half, y: center.y - dy * half),
                endPoint: CGPoint(x: center.x + dx * half, y: center.y + dy * half)
            )
        )
    }

    private func paint(_ ink: FukeiSealArt.Ink, color: Color, lineWidth: CGFloat, context: inout GraphicsContext) {
        let style = FillStyle(eoFill: ink.evenOdd)
        context.fill(ink.fill, with: .color(color), style: style)
        guard lineWidth > 0 else { return }
        context.stroke(
            ink.stroke,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func strokeWidth(_ unit: Double, floor: Double, side: CGFloat) -> CGFloat {
        guard unit > 0 else { return 0 }
        return CGFloat(max(unit, floor)) * side
    }
}

#if DEBUG
struct FukeiSealGallery: View {
    private static let luxuries: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
    private static let labels = ["0", "0.15", "0.3", "0.45", "0.6", "0.75", "0.9", "1"]
    private static let rows: [(PunctualityJudgment.StampSeason, PunctualityJudgment.StampTimeOfDay, String, String)] = [
        (.spring, .morning, "春", "朝"),
        (.summer, .afternoon, "夏", "昼"),
        (.autumn, .evening, "秋", "夕"),
        (.winter, .night, "冬", "夜"),
    ]
    private static let seed = SealSeed.seed(
        rideID: UUID(uuidString: "17117171-0171-4171-8171-171171171171")!
    )
    private static let dateText = "26.10.19"
    private static let paper = Color(red: 0.96, green: 0.93, blue: 0.88)

    var body: some View {
        GeometryReader { geo in
            let labelWidth: CGFloat = 34
            let horizontal: CGFloat = 10
            let gap: CGFloat = 3
            let columns = CGFloat(Self.luxuries.count)
            let colWidth = (geo.size.width - horizontal * 2 - labelWidth - gap * (columns - 1)) / columns
            let fullSide = max(24, colWidth - 1)
            VStack(spacing: 8) {
                Spacer(minLength: 4)
                columnHeader(colWidth: colWidth, gap: gap, labelWidth: labelWidth)
                    .padding(.horizontal, horizontal)
                ForEach(0 ..< Self.rows.count, id: \.self) { index in
                    fullRow(index, side: fullSide, colWidth: colWidth, gap: gap, labelWidth: labelWidth)
                        .padding(.horizontal, horizontal)
                }
                compactRow(colWidth: colWidth, gap: gap, labelWidth: labelWidth)
                    .padding(.horizontal, horizontal)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                Spacer(minLength: 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Self.paper.ignoresSafeArea())
    }

    private func columnHeader(colWidth: CGFloat, gap: CGFloat, labelWidth: CGFloat) -> some View {
        HStack(spacing: gap) {
            Color.clear.frame(width: labelWidth, height: 12)
            ForEach(Self.labels.indices, id: \.self) { index in
                Text(Self.labels[index])
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(width: colWidth)
            }
        }
    }

    private func fullRow(_ index: Int, side: CGFloat, colWidth: CGFloat, gap: CGFloat, labelWidth: CGFloat) -> some View {
        let row = Self.rows[index]
        return HStack(alignment: .center, spacing: gap) {
            VStack(spacing: 0) {
                Text(row.2)
                    .font(.system(size: 12, weight: .medium))
                Text(row.3)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
            .frame(width: labelWidth)
            .foregroundStyle(Color.black.opacity(0.72))
            ForEach(Self.luxuries.indices, id: \.self) { luxuryIndex in
                FukeiSealView(
                    input: FukeiSealInput(
                        luxury: Self.luxuries[luxuryIndex],
                        season: row.0,
                        timeOfDay: row.1,
                        seed: Self.seed,
                        dateText: Self.dateText,
                        detail: .full
                    )
                )
                .frame(width: side, height: side)
                .frame(width: colWidth)
            }
        }
    }

    private func compactRow(colWidth: CGFloat, gap: CGFloat, labelWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: gap) {
            Text("18pt")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: labelWidth)
            ForEach(Self.luxuries.indices, id: \.self) { index in
                FukeiSealView(
                    input: FukeiSealInput(
                        luxury: Self.luxuries[index],
                        season: .spring,
                        timeOfDay: .afternoon,
                        seed: Self.seed,
                        dateText: "",
                        detail: .compact
                    )
                )
                .frame(width: 18, height: 18)
                .frame(width: colWidth)
            }
        }
    }
}
#endif
