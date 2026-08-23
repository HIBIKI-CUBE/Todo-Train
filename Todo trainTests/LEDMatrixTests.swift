//
//  LEDMatrixTests.swift
//  Todo trainTests
//

import CoreGraphics
import Testing
@testable import Todo_train

struct LEDMatrixTests {
    @Test func departBoard_columnCount_matchesGlyphsAndGaps() {
        let expected =
            LEDMatrix.chevronRunWidth
            + LEDMatrix.groupGap
            + LEDMatrix.hatsu.width
            + LEDMatrix.kanjiGap
            + LEDMatrix.sha.width
            + LEDMatrix.groupGap
            + LEDMatrix.chevronRunWidth
        #expect(LEDMatrix.departColumnCount == expected)
        #expect(LEDMatrix.departColumnCount == 60)
        let board = LEDMatrix.departBoard()
        #expect(board.columnCount == expected)
        #expect(board.rowCount == LEDMatrix.rowCount)
        #expect(board.cells.count == expected * LEDMatrix.rowCount)
    }

    @Test func departBoard_litCount_equalsGlyphBitsOnly() {
        let expected =
            LEDMatrix.chevron.litCount * LEDMatrix.chevronRunCount * 2
            + LEDMatrix.hatsu.litCount
            + LEDMatrix.sha.litCount
        let board = LEDMatrix.departBoard()
        #expect(board.litCount == expected)
        #expect(board.cells.filter(\.on).count == expected)
        #expect(board.cells.filter { !$0.on }.count == board.cells.count - expected)
    }

    @Test func opacity_idleCellsStayDimmerThanLitGlyphs() {
        let off = LEDMatrix.Cell(on: false, chevronIndex: nil)
        let idle = LEDMatrix.opacity(for: off, phase: 0.4, lit: true)
        #expect(idle > 0)
        #expect(idle < 0.2)
        let kanji = LEDMatrix.Cell(on: true, chevronIndex: nil)
        #expect(LEDMatrix.opacity(for: kanji, phase: 0.4, lit: true) == 1)
        #expect(LEDMatrix.opacity(for: kanji, phase: 0.4, lit: false) == 0.2)
    }
}

struct LEDQuantizerTests {
    @Test func quantize_fullAndEmptyCoverage() {
        let full = LEDQuantizer.quantize(
            coverage: Array(repeating: 1, count: 8),
            columns: 4,
            rows: 2,
            threshold: 0.5
        )
        #expect(full.litCount == 8)
        #expect(full.debugArt == "####\n####")

        let empty = LEDQuantizer.quantize(
            coverage: Array(repeating: 0, count: 8),
            columns: 4,
            rows: 2,
            threshold: 0.5
        )
        #expect(empty.litCount == 0)
        #expect(empty.debugArt == "....\n....")
    }

    @Test func quantize_thresholdIsInclusiveAndWholeCell() {
        let glyph = LEDQuantizer.quantize(
            coverage: [0.37, 0.38, 0.9, 0.1],
            columns: 2,
            rows: 2,
            threshold: 0.38
        )
        #expect(glyph.pixel(row: 0, col: 0) == false)
        #expect(glyph.pixel(row: 0, col: 1) == true)
        #expect(glyph.pixel(row: 1, col: 0) == true)
        #expect(glyph.pixel(row: 1, col: 1) == false)
    }

    @Test func kanji_areDistinctQuantizedHiraginoGlyphs() {
        let hatsu = LEDMatrix.hatsu
        let sha = LEDMatrix.sha
        #expect(hatsu.width == LEDQuantizer.kanjiSize)
        #expect(hatsu.height == LEDQuantizer.kanjiSize)
        #expect(sha.width == LEDQuantizer.kanjiSize)
        #expect(sha.height == LEDQuantizer.kanjiSize)
        #expect(hatsu.litCount >= 35)
        #expect(sha.litCount >= 35)
        #expect(hatsu.litCount < 130)
        #expect(sha.litCount < 130)
        #expect(hatsu.debugArt != sha.debugArt)

        let mid = hatsu.width / 2
        let hatRows = (hatsu.height / 8)..<(hatsu.height / 3)
        // 発: 癶 is two ink clusters in the upper third (skip empty padding rows).
        let hatsuTopLeft = hatRows.reduce(0) { total, row in
            total + (0..<mid).reduce(0) { $0 + (hatsu.pixel(row: row, col: $1) ? 1 : 0) }
        }
        let hatsuTopRight = hatRows.reduce(0) { total, row in
            total + (mid..<hatsu.width).reduce(0) { $0 + (hatsu.pixel(row: row, col: $1) ? 1 : 0) }
        }
        #expect(hatsuTopLeft >= 6)
        #expect(hatsuTopRight >= 3)

        // 車: a vertical spine through the middle columns.
        let shaSpine = (0..<sha.height).reduce(0) { total, row in
            total + ((sha.pixel(row: row, col: mid - 1) || sha.pixel(row: row, col: mid)) ? 1 : 0)
        }
        #expect(shaSpine >= 8)

        // 車 must keep a counter (田). A fat downsample fills it.
        let holeRows = (sha.height / 4)..<(sha.height * 3 / 4)
        let holeCols = (sha.width / 4)..<(sha.width * 3 / 4)
        let holeOff = holeRows.reduce(0) { total, row in
            total + holeCols.reduce(0) { $0 + (sha.pixel(row: row, col: $1) ? 0 : 1) }
        }
        #expect(holeOff >= 4)
    }
}
