//
//  TrainLayoutTests.swift
//  Todo trainTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Todo_train

struct TrainLayoutTests {
    @Test func shouldSplitHub_requiresCompactHeight() {
        #expect(TrainLayout.shouldSplitHub(availableWidth: 900, compactHeight: false) == false)
        #expect(TrainLayout.shouldSplitHub(availableWidth: 900, compactHeight: true) == true)
        #expect(TrainLayout.shouldSplitHub(availableWidth: 0, compactHeight: true) == true)
    }

    @Test func shouldSplitHub_skipsNarrowWindows() {
        #expect(TrainLayout.shouldSplitHub(availableWidth: 320, compactHeight: true) == false)
        #expect(TrainLayout.hubServicePaneWidth(for: 320) == 0)
    }

    @Test func hubServicePaneWidth_capsAtIdeal() {
        let pane = TrainLayout.hubServicePaneWidth(for: 932)
        #expect(pane <= TrainLayout.hubServicePaneIdealWidth)
        #expect(pane >= TrainLayout.hubServicePaneMinimumWidth)
        #expect(932 - pane >= TrainLayout.hubMinimumTicketPaneWidth)
    }

    @Test func ticketFaceSize_followsContainerWidth() {
        let wide = TrainLayout.ticketFaceSize(containerWidth: 400)
        let narrow = TrainLayout.ticketFaceSize(containerWidth: 200)
        #expect(wide.width == 400 - MarsTicketSpec.HubStack.horizontalInset * 2)
        #expect(narrow.width < wide.width)
        #expect(abs(wide.height - MarsTicketSpec.height(forWidth: wide.width)) < 0.001)
    }

    @Test func presentedCardSize_ignoresStaleSlotWidth() {
        let overlay: CGFloat = 280
        let size = TrainLayout.presentedCardSize(overlayWidth: overlay)
        let staleSlot: CGFloat = 430
        #expect(size.width < staleSlot)
        #expect(size.width == overlay - MarsTicketSpec.HubStack.horizontalInset * 2)
    }

    @Test func slotFrames_dropsUnreportedIDs() {
        let kept = UUID()
        let stale = UUID()
        let reported = [kept: CGRect(x: 0, y: 0, width: 10, height: 10)]
        let result = TrainLayout.slotFrames(reported: reported, keeping: [kept, stale])
        #expect(result[kept] != nil)
        #expect(result[stale] == nil)
    }

    @Test func clampedLandingRect_shrinksToContainer() {
        let huge = CGRect(x: 0, y: 0, width: 500, height: 400)
        let clamped = TrainLayout.clampedLandingRect(huge, containerSize: CGSize(width: 200, height: 400))
        let face = TrainLayout.ticketFaceSize(containerWidth: 200)
        #expect(clamped.width <= face.width + 0.5)
        #expect(abs(clamped.height - MarsTicketSpec.height(forWidth: clamped.width)) < 0.5)
        #expect(abs(clamped.midX - huge.midX) < 0.5)
    }
}
