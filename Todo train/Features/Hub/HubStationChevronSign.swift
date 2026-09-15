//
//  HubStationChevronSign.swift
//  Todo train
//
//  Station LED board: ">> 発車 >>" as one-pitch on/off dots on a full lattice.
//  Hub present overlay only (not a sibling in the deck ForEach).
//

import SwiftUI

struct HubDepartLEDSign: View {
    var canBoard: Bool
    var ticketWidth: CGFloat
    var ticketHeight: CGFloat

    private var signHeight: CGFloat {
        ticketHeight * MarsTicketSpec.HubStack.departSignHeightRatio
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !canBoard)) { timeline in
            let phase = chasePhase(at: timeline.date)
            LEDMatrixCanvas(board: LEDMatrix.departBoard(), phase: phase, lit: canBoard)
                .padding(5)
                .frame(width: ticketWidth, height: signHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background { StationSignHousing(rimLit: canBoard) }
        }
        .frame(width: ticketWidth, height: signHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .drawingGroup()
    }

    private func chasePhase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
    }
}

enum LEDPhosphor {
    static let on = Color(red: 0.42, green: 0.90, blue: 0.58)
    static let off = Color(red: 0.10, green: 0.22, blue: 0.16)
    static let housing = Color(red: 0.04, green: 0.055, blue: 0.05)
    static let rim = Color(red: 0.16, green: 0.36, blue: 0.26)
}

struct StationSignHousing: View {
    var rimLit: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LEDPhosphor.housing)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(LEDPhosphor.rim.opacity(rimLit ? 0.55 : 0.28), lineWidth: 1)
            }
    }
}

enum LEDMatrix {
    static let rowCount = LEDQuantizer.kanjiSize
    static let latticeRows = 24
    static let chevronRunCount = 2
    static let chevronGap = 1
    static let kanjiGap = 2
    static let groupGap = 2

    struct Glyph: Equatable {
        var width: Int
        var height: Int
        /// One row per entry; bit `(width - 1)` is the leftmost column.
        var rows: [UInt32]

        func pixel(row: Int, col: Int) -> Bool {
            guard row >= 0, row < height, col >= 0, col < width else { return false }
            let shift = width - 1 - col
            return (rows[row] & (1 << shift)) != 0
        }

        var litCount: Int {
            (0..<height).reduce(0) { total, row in
                total + (0..<width).reduce(0) { $0 + (pixel(row: row, col: $1) ? 1 : 0) }
            }
        }

        var debugArt: String {
            (0..<height).map { row in
                (0..<width).map { pixel(row: row, col: $0) ? "#" : "." }.joined()
            }.joined(separator: "\n")
        }
    }

    struct Cell: Equatable {
        var on: Bool
        /// Set on `>` cells; sheen uses column, not this index.
        var chevronIndex: Int?
    }

    struct Board: Equatable {
        var columnCount: Int
        var rowCount: Int
        var cells: [Cell]

        func cell(row: Int, column: Int) -> Cell {
            cells[row * columnCount + column]
        }

        var litCount: Int {
            cells.reduce(0) { $0 + ($1.on ? 1 : 0) }
        }
    }

    /// Greater-than from the bundled 16-dot font — not a hand-drawn bitmap.
    static let chevron = LEDQuantizer.glyph(for: ">")

    /// 発 from bundled jiskan16.
    static let hatsu = LEDQuantizer.glyph(for: "発")

    /// 車 from bundled jiskan16.
    static let sha = LEDQuantizer.glyph(for: "車")

    static var chevronRunWidth: Int {
        chevronRunCount * chevron.width + (chevronRunCount - 1) * chevronGap
    }

    static var departColumnCount: Int {
        chevronRunWidth + groupGap + hatsu.width + kanjiGap + sha.width + groupGap + chevronRunWidth
    }

    static func departBoard() -> Board {
        var cells = Array(
            repeating: Cell(on: false, chevronIndex: nil),
            count: departColumnCount * rowCount
        )
        var x = 0
        stampChevronRun(into: &cells, at: &x)
        x += groupGap
        stamp(hatsu, into: &cells, column: x, chevronIndex: nil)
        x += hatsu.width + kanjiGap
        stamp(sha, into: &cells, column: x, chevronIndex: nil)
        x += sha.width + groupGap
        stampChevronRun(into: &cells, at: &x)
        return Board(columnCount: departColumnCount, rowCount: rowCount, cells: cells)
    }

    /// Half-width of the highlight as a fraction of the content row.
    /// Wide so it reads as a face washing across, not a scanline.
    static let sheenBand = 0.30
    /// Fraction of the loop spent sweeping; the rest is a rest on the right.
    static let sheenTravel = 0.80
    static let sheenFull = 1.0
    static let sheenBase = 0.42
    /// LED-like brightness rungs. Enough to move smoothly, few enough to stay stepped.
    static let sheenSteps = 6

    /// Raised cosine 0...1, then snapped to `sheenSteps` rungs.
    static func sheen(at column: Int, phase: Double) -> Double {
        let span = Double(max(departColumnCount - 1, 1))
        let x = Double(column) / span
        let travel = min(max(phase / sheenTravel, 0), 1)
        let center = travel * (1 + 2 * sheenBand) - sheenBand
        let u = max(0, 1 - abs(x - center) / sheenBand)
        let smooth = 0.5 - 0.5 * cos(u * .pi)
        let rungs = Double(sheenSteps - 1)
        return (smooth * rungs).rounded() / rungs
    }

    static func opacity(for cell: Cell, phase: Double, lit: Bool, column: Int = 0) -> Double {
        guard cell.on else { return lit ? 0.18 : 0.10 }
        guard lit else { return 0.22 }
        return sheenBase + sheen(at: column, phase: phase) * (sheenFull - sheenBase)
    }

    private static func stampChevronRun(into cells: inout [Cell], at x: inout Int) {
        for index in 0..<chevronRunCount {
            stamp(chevron, into: &cells, column: x, chevronIndex: index)
            x += chevron.width
            if index < chevronRunCount - 1 {
                x += chevronGap
            }
        }
    }

    private static func stamp(
        _ glyph: Glyph,
        into cells: inout [Cell],
        column: Int,
        chevronIndex: Int?
    ) {
        let y0 = (rowCount - glyph.height) / 2
        for row in 0..<glyph.height {
            for col in 0..<glyph.width {
                guard glyph.pixel(row: row, col: col) else { continue }
                let dest = (y0 + row) * departColumnCount + column + col
                cells[dest] = Cell(on: true, chevronIndex: chevronIndex)
            }
        }
    }
}

private struct LEDMatrixCanvas: View {
    var board: LEDMatrix.Board
    var phase: Double
    var lit: Bool

    var body: some View {
        Canvas { context, size in
            let rows = LEDMatrix.latticeRows
            guard rows > 0, size.width > 0, size.height > 0 else { return }
            let pitch = size.height / CGFloat(rows)
            guard pitch > 0 else { return }
            let cols = max(Int((size.width / pitch).rounded(.down)), 1)
            let gridW = pitch * CGFloat(cols)
            let originX = (size.width - gridW) / 2
            let originY = (size.height - pitch * CGFloat(rows)) / 2
            let dot = pitch * 0.78
            let inset = (pitch - dot) / 2
            let x0 = max((cols - board.columnCount) / 2, 0)
            let y0 = max((rows - board.rowCount) / 2, 0)
            let offAlpha: Double = lit ? 1 : 0.7

            for row in 0..<rows {
                for column in 0..<cols {
                    let cr = row - y0
                    let cc = column - x0
                    let cell: LEDMatrix.Cell
                    if cr >= 0, cr < board.rowCount, cc >= 0, cc < board.columnCount {
                        cell = board.cell(row: cr, column: cc)
                    } else {
                        cell = LEDMatrix.Cell(on: false, chevronIndex: nil)
                    }
                    let rect = CGRect(
                        x: originX + CGFloat(column) * pitch + inset,
                        y: originY + CGFloat(row) * pitch + inset,
                        width: dot,
                        height: dot
                    )
                    if cell.on {
                        let alpha = LEDMatrix.opacity(
                            for: cell,
                            phase: phase,
                            lit: lit,
                            column: max(cc, 0)
                        )
                        if lit {
                            let glow = rect.insetBy(dx: -dot * 0.06, dy: -dot * 0.06)
                            context.fill(
                                Path(ellipseIn: glow),
                                with: .color(LEDPhosphor.on.opacity(alpha * 0.18))
                            )
                        }
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(LEDPhosphor.on.opacity(alpha))
                        )
                    } else {
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(LEDPhosphor.off.opacity(offAlpha))
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
        VStack(spacing: 16) {
            HubDepartLEDSign(canBoard: true, ticketWidth: 320, ticketHeight: 210)
            HubDepartLEDSign(canBoard: false, ticketWidth: 320, ticketHeight: 210)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(MarsTicketSpec.paper)
                .frame(width: 320, height: 210)
        }
    }
}
