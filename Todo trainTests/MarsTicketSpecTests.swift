//
//  MarsTicketSpecTests.swift
//  Todo trainTests
//

import CoreGraphics
import Testing
@testable import Todo_train

struct MarsTicketSpecTests {
    @Test func aspectRatio_matchesPhysicalMarsTicket() {
        #expect(abs(MarsTicketSpec.aspectRatio - (85.0 / 57.5)) < 0.0001)
        #expect(abs(MarsTicketSpec.height(forWidth: 340) - 230) < 0.01)
    }

    @Test func cornerRadius_isNearSquareNotIOSCard() {
        #expect(MarsTicketSpec.cornerRadius <= MarsTicketSpec.cornerRadiusMax)
        #expect(MarsTicketSpec.cornerRadiusMax <= 3)
        #expect(MarsTicketSpec.cornerRadius < 8)
    }

    @Test func titleAndFare_dominateViaAndTerminal() {
        // Destination title + fare-scale minutes. No printed 券種.
        #expect(MarsTicketSpec.titlePointSize > MarsTicketSpec.viaPointSize)
        #expect(MarsTicketSpec.titlePointSize > MarsTicketSpec.terminalPointSize)
        #expect(MarsTicketSpec.farePointSize > MarsTicketSpec.titlePointSize)
        #expect(MarsTicketSpec.farePointSize > MarsTicketSpec.viaPointSize)
        #expect(MarsTicketSpec.validityDayPointSize > MarsTicketSpec.metaPointSize)
    }

    @Test func paperColors_untaggedIsFixedNotSalmonEdmondson() {
        // Salmon Edmondson stock must not be the untagged Mars paper (#F3D4C4 family).
        #expect(TicketStockColor.untagged.paper.red == 0xD5)
        #expect(TicketStockColor.untagged.paper.green == 0xE6)
        #expect(TicketStockColor.untagged.paper.blue == 0xEA)
        #expect(MarsTicketSpec.aspectWidth == 85)
        #expect(MarsTicketSpec.aspectHeight == 57.5)
    }

    @Test func content_doesNotInventStationsOrYen() {
        let content = MarsTicketContent(
            title: "週次レビュー",
            minutes: 30,
            tagNames: ["仕事"],
            colorHex: "#0091FF"
        )
        #expect(content.title == "週次レビュー")
        #expect(content.validityLine.contains("30分間有効"))
        #expect(!content.validityLine.contains("¥"))
        #expect(content.tagNames == ["仕事"])
        #expect(content.colorHex == "#0091FF")
    }

    @Test func hubPresent_timetablePlatePairsWithDepartLED() {
        #expect(
            abs(
                MarsTicketSpec.HubStack.timetablePlateHeightRatio
                    - MarsTicketSpec.HubStack.departSignHeightRatio
            ) < 0.001
        )
        #expect(
            abs(MarsTicketSpec.HubStack.timetablePlateHeight(ticketHeight: 230) - 101.2) < 0.01
        )
    }
}
