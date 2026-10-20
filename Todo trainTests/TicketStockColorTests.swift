//
//  TicketStockColorTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
@testable import Todo_train

@MainActor
struct TicketStockColorTests {
    @Test func untagged_matchesCanonicalMarsCyan() {
        #expect(TicketStockColor.untagged.paper.red == 0xD5)
        #expect(TicketStockColor.untagged.paper.green == 0xE6)
        #expect(TicketStockColor.untagged.paper.blue == 0xEA)
        #expect(TicketStockColor.untagged.band.red == 0xE7)
        #expect(TicketStockColor.untagged.band.green == 0xF1)
        #expect(TicketStockColor.untagged.band.blue == 0xF3)
        #expect(TicketStockColor.stock(for: nil) == TicketStockColor.untagged)
        #expect(TicketStockColor.stock(for: "") == TicketStockColor.untagged)
    }

    @Test func unknownHex_fallsBackToUntagged() {
        #expect(TicketStockColor.stock(for: "#DEAD00") == TicketStockColor.untagged)
        #expect(TicketStockColor.stock(for: "not-a-color") == TicketStockColor.untagged)
    }

    @Test func paletteHexes_eachHaveDistinctStock() {
        for swatch in TagPalette.colors {
            let stock = TicketStockColor.stock(for: swatch.hex)
            #expect(stock != TicketStockColor.untagged)
            #expect(TicketStockColor.stock(for: swatch.hex.lowercased()) == stock)
        }
    }

    @Test func winningColorHex_emptyIsNil() {
        let none: [(sortOrder: Int, colorHex: String)] = []
        #expect(TicketStockColor.winningColorHex(from: none) == nil)
    }

    @Test func winningColorHex_singleTag() {
        #expect(
            TicketStockColor.winningColorHex(from: [
                (sortOrder: 2, colorHex: "#30A46C"),
            ]) == "#30A46C"
        )
    }

    @Test func winningColorHex_lowestSortOrderWins() {
        #expect(
            TicketStockColor.winningColorHex(from: [
                (sortOrder: 1, colorHex: "#30A46C"),
                (sortOrder: 0, colorHex: "#0091FF"),
            ]) == "#0091FF"
        )
    }

    @Test func grayStock_isNotUntaggedCyan() {
        let gray = TicketStockColor.stock(for: "#888888")
        #expect(gray != TicketStockColor.untagged)
        #expect(gray.paper.red == gray.paper.green)
        #expect(gray.paper.green == gray.paper.blue)
    }
}

@MainActor
struct TicketStockColorModelTests {
    @Test func marsContent_usesWinningTagColorAndAllNames() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let work = Tag(name: "仕事", colorHex: "#0091FF", sortOrder: 0)
        let home = Tag(name: "家", colorHex: "#30A46C", sortOrder: 1)
        let ticket = Ticket(title: "請求書", estimatedSeconds: 900)
        context.insert(work)
        context.insert(home)
        context.insert(ticket)
        ticket.tags = [home, work]
        try context.save()

        let content = MarsTicketContent(ticket: ticket)
        #expect(content.tagNames == ["仕事", "家"])
        #expect(content.colorHex == "#0091FF")
        #expect(TicketStockColor.stock(for: content.colorHex) != TicketStockColor.untagged)
    }

    @Test func marsContent_untaggedKeepsNilHex() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let ticket = Ticket(title: "メモ", estimatedSeconds: 600)
        context.insert(ticket)
        try context.save()

        let content = MarsTicketContent(ticket: ticket)
        #expect(content.tagNames.isEmpty)
        #expect(content.colorHex == nil)
        #expect(TicketStockColor.stock(for: content.colorHex) == TicketStockColor.untagged)
    }
}
