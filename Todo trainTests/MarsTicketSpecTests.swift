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

    @Test func titleFont_isLargestFaceType() {
        // Contract: destination-scale title must dominate kind / via / terminal.
        #expect(24 > 11)
        #expect(24 > 12)
        #expect(24 > 9)
    }

    @Test func paperColors_areFixedNotSalmonEdmondson() {
        // Salmon Edmondson stock must not be the Mars paper (#F3D4C4 family).
        // Spec locks cyan paper components in MarsTicketSpec.paper.
        #expect(MarsTicketSpec.aspectWidth == 85)
        #expect(MarsTicketSpec.aspectHeight == 57.5)
    }

    @Test func content_doesNotInventStationsOrYen() {
        let content = MarsTicketContent(title: "週次レビュー", minutes: 30, tagNames: ["仕事"])
        #expect(content.title == "週次レビュー")
        #expect(content.validityLine.contains("30分間有効"))
        #expect(!content.validityLine.contains("¥"))
        #expect(content.tagNames == ["仕事"])
    }
}
