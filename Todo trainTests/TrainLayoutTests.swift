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

    @Test func slotFrames_fromDeckFrameMatchPeekLayout() {
        let back = UUID()
        let front = UUID()
        let deck = CGRect(x: 10, y: 80, width: 390, height: 500)
        let frames = TrainLayout.slotFrames(deckFrame: deck, orderedIDs: [back, front])
        let face = TrainLayout.ticketFaceSize(containerWidth: 390)
        let x = deck.minX + (deck.width - face.width) / 2
        #expect(frames[back] == CGRect(x: x, y: 80, width: face.width, height: face.height))
        #expect(frames[front] == CGRect(
            x: x,
            y: 80 + MarsTicketSpec.HubStack.peekStep,
            width: face.width,
            height: face.height
        ))
        #expect(TrainLayout.slotFrames(deckFrame: .zero, orderedIDs: [back]).isEmpty)
        #expect(TrainLayout.slotFrames(deckFrame: deck, orderedIDs: []).isEmpty)
    }

    @Test func slotFrames_scrollMustNotPublishWhileIdle() {
        let id = UUID()
        let parked = [id: CGRect(x: 0, y: 100, width: 200, height: 120)]
        let scrolled = [id: CGRect(x: 0, y: 40, width: 200, height: 120)]
        #expect(
            TrainLayout.shouldPublishSlotFrames(
                needsLiveFrames: false,
                reported: scrolled,
                published: parked
            ) == false
        )
        #expect(
            TrainLayout.shouldPublishSlotFrames(
                needsLiveFrames: true,
                reported: scrolled,
                published: parked
            )
        )
        #expect(
            TrainLayout.shouldPublishSlotFrames(
                needsLiveFrames: true,
                reported: scrolled,
                published: scrolled
            ) == false
        )
        #expect(
            TrainLayout.slotFramesMatch(
                parked,
                [id: CGRect(x: 0, y: 100.2, width: 200, height: 120)]
            )
        )
        #expect(
            !TrainLayout.slotFramesMatch(
                parked,
                [id: CGRect(x: 0, y: 40, width: 200, height: 120)]
            )
        )
    }

    @Test func clampedLandingRect_shrinksToContainer() {
        let huge = CGRect(x: 0, y: 0, width: 500, height: 400)
        let clamped = TrainLayout.clampedLandingRect(huge, containerSize: CGSize(width: 200, height: 400))
        let face = TrainLayout.ticketFaceSize(containerWidth: 200)
        #expect(clamped.width <= face.width + 0.5)
        #expect(abs(clamped.height - MarsTicketSpec.height(forWidth: clamped.width)) < 0.5)
        #expect(abs(clamped.midX - huge.midX) < 0.5)
    }

    @Test func shouldShowTimetablePlate_hidesWhenOverlayIsShort() {
        let ticketHeight: CGFloat = 150
        let plate = MarsTicketSpec.HubStack.timetablePlateHeight(ticketHeight: ticketHeight)
        #expect(
            TrainLayout.shouldShowTimetablePlate(
                overlayHeight: 800,
                ticketHeight: ticketHeight,
                plateHeight: plate
            )
        )
        #expect(
            !TrainLayout.shouldShowTimetablePlate(
                overlayHeight: 280,
                ticketHeight: ticketHeight,
                plateHeight: plate
            )
        )
    }
}
