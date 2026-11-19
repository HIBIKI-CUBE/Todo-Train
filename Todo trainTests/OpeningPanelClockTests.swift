//
//  OpeningPanelClockTests.swift
//  Todo trainTests
//
//  桁の寸法、コロン、12/24 の出し方。テンポの受け入れは OpeningPanelStateTests。
//

import SwiftUI
import UIKit
import Testing
@testable import Todo_train

struct OpeningPanelClockTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func metricsMatchTheFinalMock() {
        #expect(OpeningPanelClockMetrics.digitWidth == 50)
        #expect(OpeningPanelClockMetrics.digitHeight == 100)
        #expect(OpeningPanelClockMetrics.horizontalSegment == CGSize(width: 38, height: 7))
        #expect(OpeningPanelClockMetrics.verticalSegment == CGSize(width: 7, height: 42))
        #expect(OpeningPanelClockMetrics.gap == 9)
        #expect(OpeningPanelClockMetrics.colonWidth == 7)
        #expect(OpeningPanelClockMetrics.colonHeight == 38)
        #expect(OpeningPanelClockMetrics.colonBarHeight == 7)
        #expect(OpeningPanelClockMetrics.faceWidth == 243)
        #expect(OpeningPanelClockMetrics.faceHeight == 100)
        #expect(OpeningPanelClockMetrics.middleTop == 46.5)
        #expect(OpeningPanelClockMetrics.secondsFontSize == 11)
        #expect(OpeningPanelClockMetrics.secondsTrackingEm == 0.04)
        #expect(OpeningPanelClockMetrics.secondsOpacity == 0.8)
        #expect(OpeningPanelClockMetrics.secondsTrailing == 7)
        #expect(OpeningPanelClockMetrics.secondsBottom == 4)

        #expect(OpeningPanelClockLayout.segment(.a, digit: 0) == CGRect(x: 6, y: 0, width: 38, height: 7))
        #expect(OpeningPanelClockLayout.segment(.g, digit: 0) == CGRect(x: 6, y: 46.5, width: 38, height: 7))
        #expect(OpeningPanelClockLayout.segment(.d, digit: 0) == CGRect(x: 6, y: 93, width: 38, height: 7))
        #expect(OpeningPanelClockLayout.segment(.f, digit: 0) == CGRect(x: 0, y: 5, width: 7, height: 42))
        #expect(OpeningPanelClockLayout.segment(.b, digit: 0) == CGRect(x: 43, y: 5, width: 7, height: 42))
        #expect(OpeningPanelClockLayout.segment(.e, digit: 0) == CGRect(x: 0, y: 53, width: 7, height: 42))
        #expect(OpeningPanelClockLayout.segment(.c, digit: 0) == CGRect(x: 43, y: 53, width: 7, height: 42))
        #expect(OpeningPanelClockLayout.digitOrigin(1) == CGPoint(x: 59, y: 0))
        #expect(OpeningPanelClockLayout.digitOrigin(2) == CGPoint(x: 134, y: 0))
        #expect(OpeningPanelClockLayout.digitOrigin(3) == CGPoint(x: 193, y: 0))
        #expect(OpeningPanelClockLayout.colonBars() == [
            CGRect(x: 118, y: 31, width: 7, height: 7),
            CGRect(x: 118, y: 62, width: 7, height: 7),
        ])
        let last = OpeningPanelClockLayout.digitOrigin(3).x + OpeningPanelClockMetrics.digitWidth
        #expect(last == OpeningPanelClockMetrics.faceWidth)

        let window = CGSize(width: 148, height: 88)
        #expect(abs(OpeningPanelClockMetrics.scale(fitting: window) - (134 / 243)) < 0.000_001)
    }

    @Test func glyphMapMatchesTheMock() {
        #expect(OpeningPanelClockGlyph.segments(for: "0") == [.a, .b, .c, .d, .e, .f])
        #expect(OpeningPanelClockGlyph.segments(for: "1") == [.b, .c])
        #expect(OpeningPanelClockGlyph.segments(for: "2") == [.a, .b, .g, .e, .d])
        #expect(OpeningPanelClockGlyph.segments(for: "3") == [.a, .b, .g, .c, .d])
        #expect(OpeningPanelClockGlyph.segments(for: "4") == [.f, .g, .b, .c])
        #expect(OpeningPanelClockGlyph.segments(for: "5") == [.a, .f, .g, .c, .d])
        #expect(OpeningPanelClockGlyph.segments(for: "6") == [.a, .f, .g, .e, .d, .c])
        #expect(OpeningPanelClockGlyph.segments(for: "7") == [.a, .b, .c])
        #expect(OpeningPanelClockGlyph.segments(for: "8") == Set(OpeningPanelClockSegment.allCases))
        #expect(OpeningPanelClockGlyph.segments(for: "9") == [.a, .b, .c, .d, .f, .g])
        #expect(OpeningPanelClockGlyph.segments(for: " ").isEmpty)
    }

    @Test func amberMatchesTheMockAndGlowIsNotASeparateInk() {
        let amber = components(OpeningPanelTokens.Palette.amber)
        #expect(abs(amber.red - 1) < 0.001)
        #expect(abs(amber.green - 176 / 255) < 0.001)
        #expect(abs(amber.blue - 0) < 0.001)
        #expect(abs(amber.alpha - 0.85) < 0.001)
        let dim = components(OpeningPanelTokens.Palette.amberDim)
        #expect(abs(dim.red - 1) < 0.001)
        #expect(abs(dim.green - 176 / 255) < 0.001)
        #expect(abs(dim.alpha - 0.14) < 0.001)
    }

    @Test func readout_blankDigitsThenLiveColonAndHourCycle() {
        let afternoon = at(hour: 15, minute: 48, second: 20)
        let blank = OpeningPanelClockReadout.make(
            stage: .backlight,
            cycle: .twentyFour,
            date: afternoon,
            calendar: calendar
        )
        #expect(blank.visible)
        #expect(blank.pattern == "    ")
        #expect(!blank.colonLit)
        #expect(blank.seconds == nil)
        #expect(blank.spoken == "起動中")

        let eight = OpeningPanelClockReadout.make(
            stage: .digits("8"),
            cycle: .twentyFour,
            date: afternoon,
            calendar: calendar
        )
        #expect(eight.pattern == "8   ")
        #expect(!eight.colonLit)
        #expect(eight.seconds == nil)

        let pair = OpeningPanelClockReadout.make(
            stage: .digits("88"),
            cycle: .twentyFour,
            date: afternoon,
            calendar: calendar
        )
        #expect(pair.pattern == "88  ")
        #expect(pair.colonLit)

        let full = OpeningPanelClockReadout.make(
            stage: .digits("8888"),
            cycle: .twentyFour,
            date: afternoon,
            calendar: calendar
        )
        #expect(full.pattern == "8888")
        #expect(full.colonLit)

        let cleared = OpeningPanelClockReadout.make(
            stage: .blank,
            cycle: .twentyFour,
            date: afternoon,
            calendar: calendar
        )
        #expect(cleared.pattern == "    ")
        #expect(!cleared.colonLit)
        #expect(cleared.visible)

        let dark = OpeningPanelClockReadout.make(
            stage: .dark,
            cycle: .twelve,
            date: afternoon,
            calendar: calendar
        )
        #expect(!dark.visible)
        #expect(dark.seconds == nil)
        #expect(dark.spoken == "消灯")

        #expect(OpeningPanelClockReadout.millisecond(of: Date(timeIntervalSince1970: 100)) == 0)
        #expect(OpeningPanelClockReadout.millisecond(of: Date(timeIntervalSince1970: 100.25)) == 250)
        #expect(OpeningPanelClockReadout.millisecond(of: Date(timeIntervalSince1970: 100.5)) == 500)
        #expect(OpeningPanelClockReadout.millisecond(of: Date(timeIntervalSince1970: 100.75)) == 750)

        let on = live(.twentyFour, at(hour: 15, minute: 48, second: 20, millisecond: 250))
        #expect(on.pattern == "1548")
        #expect(on.colonLit)
        #expect(on.seconds == "20")
        #expect(on.spoken == "15時48分20秒")

        let off = live(.twentyFour, at(hour: 15, minute: 48, second: 20, millisecond: 500))
        #expect(!off.colonLit)
        #expect(off.seconds == "20")

        let twelve = live(.twelve, afternoon)
        #expect(twelve.pattern == "0348")
        #expect(twelve.spoken == "3時48分20秒")

        let midnight = at(hour: 0, minute: 5, second: 7)
        #expect(live(.twentyFour, midnight).pattern == "0005")
        #expect(live(.twelve, midnight).pattern == "1205")

        let noon = at(hour: 12, minute: 0, second: 0)
        #expect(live(.twentyFour, noon).pattern == "1200")
        #expect(live(.twelve, noon).pattern == "1200")

        let late = at(hour: 23, minute: 59, second: 59)
        #expect(live(.twentyFour, late).pattern == "2359")
        #expect(live(.twelve, late).pattern == "1159")
    }

    private func live(_ cycle: OpeningPanelHourCycle, _ date: Date) -> OpeningPanelClockReadout {
        OpeningPanelClockReadout.make(stage: .live, cycle: cycle, date: date, calendar: calendar)
    }

    private func at(hour: Int, minute: Int, second: Int, millisecond: Int = 0) -> Date {
        let base = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 1,
                day: 2,
                hour: hour,
                minute: minute,
                second: second
            )
        )!
        return base.addingTimeInterval(Double(millisecond) / 1_000)
    }

    private func components(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}
