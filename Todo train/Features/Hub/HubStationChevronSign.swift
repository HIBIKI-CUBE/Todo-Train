//
//  HubStationChevronSign.swift
//  Todo train
//
//  Station LED board: ">>> 発車 >>>" as one-pitch on/off dots.
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
                .padding(.horizontal, signHeight * 0.08)
                .padding(.vertical, signHeight * 0.08)
                .frame(width: ticketWidth, height: signHeight)
                .clipped()
                .background { housing }
        }
        .frame(width: ticketWidth, height: signHeight)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .drawingGroup()
    }

    private var housing: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.black.opacity(0.9))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(TrainTheme.signalGreen.opacity(canBoard ? 0.5 : 0.18), lineWidth: 1.2)
            }
            .shadow(color: TrainTheme.signalGreen.opacity(canBoard ? 0.4 : 0), radius: 12, y: 2)
    }

    private func chasePhase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
    }
}

enum LEDMatrix {
    static let rowCount = LEDQuantizer.kanjiSize
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
        /// 0..<chevronRunCount on both sides so chase stays in sync.
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

    static let chevron = Glyph(
        width: 5,
        height: 7,
        rows: [
            0b10000,
            0b01000,
            0b00100,
            0b00011,
            0b00100,
            0b01000,
            0b10000,
        ]
    )

    /// Quantized from Hiragino 発 — not a hand-drawn bitmap.
    static let hatsu = LEDQuantizer.glyph(for: "発")

    /// Quantized from Hiragino 車 — not a hand-drawn bitmap.
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

    static func chaseOpacity(index: Int, phase: Double, lit: Bool) -> Double {
        guard lit else { return 0.16 }
        let slot = Double(index) / Double(max(chevronRunCount, 1))
        var delta = phase - slot
        if delta < 0 { delta += 1 }
        let head = max(0, 1 - delta * 2.1)
        return 0.3 + head * 0.7
    }

    static func opacity(for cell: Cell, phase: Double, lit: Bool) -> Double {
        guard cell.on else { return lit ? 0.08 : 0.05 }
        if let index = cell.chevronIndex {
            return chaseOpacity(index: index, phase: phase, lit: lit)
        }
        return lit ? 1 : 0.2
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
            let pitch = min(
                size.width / CGFloat(board.columnCount),
                size.height / CGFloat(board.rowCount)
            )
            guard pitch > 0 else { return }
            let dot = pitch * 0.70
            let gridW = pitch * CGFloat(board.columnCount)
            let gridH = pitch * CGFloat(board.rowCount)
            let originX = (size.width - gridW) / 2
            let originY = (size.height - gridH) / 2
            let inset = (pitch - dot) / 2

            for row in 0..<board.rowCount {
                for column in 0..<board.columnCount {
                    let cell = board.cell(row: row, column: column)
                    let alpha = LEDMatrix.opacity(for: cell, phase: phase, lit: lit)
                    guard alpha > 0 else { continue }
                    let rect = CGRect(
                        x: originX + CGFloat(column) * pitch + inset,
                        y: originY + CGFloat(row) * pitch + inset,
                        width: dot,
                        height: dot
                    )
                    if cell.on, lit {
                        let glow = rect.insetBy(dx: -dot * 0.08, dy: -dot * 0.08)
                        context.fill(
                            Path(ellipseIn: glow),
                            with: .color(TrainTheme.signalGreen.opacity(alpha * 0.22))
                        )
                    }
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(TrainTheme.signalGreen.opacity(alpha))
                    )
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
        VStack(spacing: 12) {
            HubDepartLEDSign(canBoard: true, ticketWidth: 320, ticketHeight: 210)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(MarsTicketSpec.paper)
                .frame(width: 320, height: 210)
        }
    }
}
