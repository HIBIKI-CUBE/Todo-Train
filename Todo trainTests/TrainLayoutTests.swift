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

    @Test func openingPanelPlacement_keepsTheGridRatioInsideTheSafeRect() {
        let design = OpeningPanelTokens.Canvas.outer
        let safe = CGRect(x: 0, y: 0, width: 402, height: 780)
        let placed = TrainLayout.openingPanelPlacement(in: safe)
        #expect(placed.scale < 1)
        #expect(placed.size.width <= safe.width + 0.01)
        #expect(placed.size.height <= safe.height + 0.01)
        #expect(abs(placed.size.width / design.width - placed.scale) < 0.001)
        #expect(abs(placed.size.height / design.height - placed.scale) < 0.001)
        #expect(abs(placed.origin.x - (safe.width - placed.size.width) / 2) < 0.01)
        #expect(abs(placed.origin.y - (safe.height - placed.size.height) / 2) < 0.01)
    }

    @Test func openingPanelPlacement_scalesUpWhenTheSafeRectIsLarger() {
        let safe = CGRect(x: 10, y: 20, width: 440, height: 900)
        let placed = TrainLayout.openingPanelPlacement(in: safe)
        #expect(placed.scale > 1)
        #expect(placed.origin.x >= safe.minX - 0.01)
        #expect(placed.origin.y >= safe.minY - 0.01)
        #expect(placed.origin.x + placed.size.width <= safe.maxX + 0.01)
        #expect(placed.origin.y + placed.size.height <= safe.maxY + 0.01)
    }

    @Test func openingPanelPlacement_unmeasuredSideKeepsTheDesignLength() {
        let placed = TrainLayout.openingPanelPlacement(in: .zero)
        #expect(placed.scale == 1)
        #expect(placed.size == OpeningPanelTokens.Canvas.outer)
    }

    @Test func openingPanelHits_clear44ExceptPackedRows_andDoNotOverlap() {
        let targets = OpeningPanelHitLayout.board(minimum: 44, ticketRows: 5)
        let packed: Set<OpeningPanelHitLayout.ID> = [
            .ticketRow(0), .ticketRow(1), .ticketRow(2), .ticketRow(3), .ticketRow(4)
        ]
        #expect(targets.count == 10 + 5)
        for target in targets {
            #expect(hitContains(target.hit, target.visual), "\(target.id)")
            #expect(target.hit.width >= 44, "\(target.id) width \(target.hit.width)")
            if packed.contains(target.id) {
                #expect(target.hit.height + 0.5 >= target.visual.height, "\(target.id)")
            } else {
                #expect(target.hit.height >= 44, "\(target.id) height \(target.hit.height)")
            }
        }
        assertNoOverlap(targets.map(\.hit))
    }

    @Test func openingPanelHits_doNotChangeAcrossPowerPictures() {
        let rows = 5
        let minimum: CGFloat = 44
        let reference = OpeningPanelHitLayout.board(minimum: minimum, ticketRows: rows)
        for _ in ["電気なし", "未確認", "確認中", "確認済み"] {
            #expect(OpeningPanelHitLayout.board(minimum: minimum, ticketRows: rows) == reference)
        }
    }

    @Test func openingPanelHits_timetableEntriesStayPutAcrossStages() {
        let entries = sampleEntries()
        let range = TimetableRangeLogic.compute(
            scheduledBlocks: entries.map(\.interval),
            referenceDay: entries[0].startsAt,
            calendar: sampleCalendar
        )
        let bounds = CGRect(x: 0, y: 0, width: 266, height: 261)
        let drawn = OpeningPanelHitLayout.timetable(
            entries: entries,
            range: range,
            bounds: bounds,
            minimum: 44
        )
        let again = OpeningPanelHitLayout.timetable(
            entries: entries,
            range: range,
            bounds: bounds,
            minimum: 44
        )
        #expect(drawn == again)
        #expect(drawn.count == entries.count * 2)
        assertNoOverlap(drawn.map(\.hit))
        for target in drawn {
            switch target.id {
            case .timetableRow:
                #expect(target.hit.width >= 44)
                #expect(hitContains(target.hit, target.visual))
            case .timetableBand:
                #expect(hitContains(target.hit, target.visual))
            case .master, .clockKey, .hourMode, .scaleToggle, .timetableKey, .sequence, .ticketsKey, .commTest, .depart, .todayRail, .ticketRow:
                break
            }
        }
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

private func hitContains(_ outer: CGRect, _ inner: CGRect) -> Bool {
    inner.minX >= outer.minX - 0.05
        && inner.minY >= outer.minY - 0.05
        && inner.maxX <= outer.maxX + 0.05
        && inner.maxY <= outer.maxY + 0.05
}

private func assertNoOverlap(_ rects: [CGRect]) {
    for index in rects.indices {
        for other in rects.indices where other > index {
            let rect = rects[index].intersection(rects[other])
            #expect(rect.width <= 0.5 || rect.height <= 0.5)
        }
    }
}

private let sampleCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func sampleEntries() -> [OpeningTimetableEntry] {
    func at(hour: Int, minute: Int) -> Date {
        sampleCalendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: hour, minute: minute))!
    }
    func entry(_ title: String, start: (Int, Int), end: (Int, Int), stops: Bool) -> OpeningTimetableEntry {
        let id = UUID()
        return OpeningTimetableEntry(
            kind: stops ? .stop(blockID: id) : .passManual(blockID: id),
            title: title,
            startsAt: at(hour: start.0, minute: start.1),
            endsAt: at(hour: end.0, minute: end.1)
        )
    }
    return [
        entry("朝会", start: (9, 30), end: (9, 45), stops: true),
        entry("定例", start: (10, 0), end: (11, 0), stops: true),
        entry("電話", start: (13, 0), end: (13, 30), stops: false),
        entry("歯医者", start: (16, 30), end: (18, 30), stops: true)
    ]
}
