//
//  DayKeyFormattingTests.swift
//  Todo trainTests
//

import Testing
@testable import Todo_train

struct DayKeyFormattingTests {
    @Test func displayDay_formatsJapaneseWeekday() {
        let text = DayKeyFormatting.displayDay(from: "2026-08-12")
        #expect(text.contains("8月12日"))
        #expect(text.contains("（"))
    }

    @Test func displayDay_passthroughInvalid() {
        #expect(DayKeyFormatting.displayDay(from: "not-a-day") == "not-a-day")
    }
}
