//
//  TicketStampBundleLayoutTests.swift
//  Todo trainTests
//

import CoreGraphics
import Testing
import TodoTrainSync
@testable import Todo_train

@Suite("Ticket stamp bundle layout")
struct TicketStampBundleLayoutTests {
    private func sampleExpanded() -> CGSize {
        CGSize(width: 260, height: MarsTicketSpec.height(forWidth: 260))
    }

    @Test func scaleIsCompactWhenFoldedAndFullWhenOpen() {
        let compact = TicketStampBundleLayout.compactTicketSize()
        let expanded = sampleExpanded()
        let folded = TicketStampBundleLayout.visualScale(compact: compact, expanded: expanded, spread: 0)
        let open = TicketStampBundleLayout.visualScale(compact: compact, expanded: expanded, spread: 1)
        let mid = TicketStampBundleLayout.visualScale(compact: compact, expanded: expanded, spread: 0.5)
        #expect(abs(folded - compact.width / expanded.width) < 0.001)
        #expect(abs(open - 1) < 0.001)
        #expect(abs(mid - (folded + open) / 2) < 0.001)
        #expect(folded < 0.55)
    }

    @Test func anglesMatchTheEndsOfTheSpread() {
        let expanded = sampleExpanded()
        let step = TicketStampBundleLayout.expandedStepDegrees(
            ticketWidth: expanded.width,
            ticketHeight: expanded.height
        )
        #expect(step > TicketStampBundleLayout.compactStepDegrees)
        let folded = TicketStampBundleLayout.angleDegrees(depth: 2, spread: 0, expandedStep: step)
        let open = TicketStampBundleLayout.angleDegrees(depth: 2, spread: 1, expandedStep: step)
        #expect(abs(folded - 2 * TicketStampBundleLayout.compactStepDegrees) < 0.001)
        #expect(abs(open - 2 * step) < 0.001)
        #expect(TicketStampBundleLayout.angleDegrees(depth: 0, spread: 1, expandedStep: step) == 0)
        #expect(open > folded)
    }

    @Test func radiusAndPivotLerpWithoutAJump() {
        let compact = TicketStampBundleLayout.compactTicketSize()
        let expanded = sampleExpanded()
        let radius0 = TicketStampBundleLayout.radius(
            compactWidth: compact.width,
            expandedWidth: expanded.width,
            spread: 0
        )
        let radius1 = TicketStampBundleLayout.radius(
            compactWidth: compact.width,
            expandedWidth: expanded.width,
            spread: 1
        )
        let radiusMid = TicketStampBundleLayout.radius(
            compactWidth: compact.width,
            expandedWidth: expanded.width,
            spread: 0.5
        )
        #expect(abs(radiusMid - (radius0 + radius1) / 2) < 0.01)
        #expect(radius1 > radius0 * 2)

        let pivot0 = TicketStampBundleLayout.pivot(compact: compact, expanded: expanded, spread: 0)
        let pivot1 = TicketStampBundleLayout.pivot(compact: compact, expanded: expanded, spread: 1)
        let pivotMid = TicketStampBundleLayout.pivot(compact: compact, expanded: expanded, spread: 0.5)
        #expect(abs(pivotMid.x - (pivot0.x + pivot1.x) / 2) < 0.01)
        #expect(abs(pivotMid.y - (pivot0.y + pivot1.y) / 2) < 0.01)
        #expect(pivot1.x > pivot0.x + 40)

        var previousX = pivot0.x
        var previousRadius = radius0
        for index in 1...20 {
            let spread = CGFloat(index) / 20
            let radius = TicketStampBundleLayout.radius(
                compactWidth: compact.width,
                expandedWidth: expanded.width,
                spread: spread
            )
            let pivot = TicketStampBundleLayout.pivot(compact: compact, expanded: expanded, spread: spread)
            let step = (radius1 - radius0) / 20
            #expect(radius + 0.01 >= previousRadius)
            #expect(pivot.x + 0.01 >= previousX)
            #expect(radius - previousRadius < step + 0.02)
            #expect(pivot.x - previousX < (pivot1.x - pivot0.x) / 20 + 0.02)
            previousRadius = radius
            previousX = pivot.x
        }
    }

    @Test func rearCardClearsTheNameAndTheOnTimeMarkWhenOpen() {
        let expanded = sampleExpanded()
        let step = TicketStampBundleLayout.expandedStepDegrees(
            ticketWidth: expanded.width,
            ticketHeight: expanded.height
        )
        let radius = TicketStampBundleLayout.radius(
            compactWidth: expanded.width,
            expandedWidth: expanded.width,
            spread: 1
        )
        let name = TicketStampBundleLayout.placed(
            TicketStampBundleLayout.titleBottomLeft(ticketWidth: expanded.width),
            depth: 1,
            ticketWidth: expanded.width,
            ticketHeight: expanded.height,
            radius: radius,
            spread: 1,
            expandedStep: step
        )
        let mark = TicketStampBundleLayout.placed(
            TicketStampBundleLayout.onTimeTitleBottomCenter(
                ticketWidth: expanded.width,
                ticketHeight: expanded.height
            ),
            depth: 1,
            ticketWidth: expanded.width,
            ticketHeight: expanded.height,
            radius: radius,
            spread: 1,
            expandedStep: step
        )
        let front = CGRect(x: 0, y: 0, width: expanded.width, height: expanded.height)
        let margin = TicketStampBundleLayout.clearanceMargin(ticketHeight: expanded.height)
        #expect(TicketStampBundleLayout.isPeeking(name, front: front, margin: margin))
        #expect(TicketStampBundleLayout.isPeeking(mark, front: front, margin: margin))
    }

    @Test func foldedFanStaysWithinTheBand() {
        let height = TicketStampBundleLayout.collapsedFanHeight
        #expect(height <= TicketStampBundleLayout.collapsedFanMax)
        #expect(height <= TicketStampBundleLayout.collapsedBandMax)
        let size = TicketStampBundleLayout.compactTicketSize()
        #expect(size.width < 160)
    }

    @Test func aRearPointMovesSmoothlyAsTheFanOpens() {
        let compact = TicketStampBundleLayout.compactTicketSize()
        let expanded = sampleExpanded()
        let step = TicketStampBundleLayout.expandedStepDegrees(
            ticketWidth: expanded.width,
            ticketHeight: expanded.height
        )
        func namePoint(_ spread: CGFloat) -> CGPoint {
            let size = TicketStampBundleLayout.ticketSize(compact: compact, expanded: expanded, spread: spread)
            let radius = TicketStampBundleLayout.radius(
                compactWidth: compact.width,
                expandedWidth: expanded.width,
                spread: spread
            )
            return TicketStampBundleLayout.placed(
                TicketStampBundleLayout.titleBottomLeft(ticketWidth: size.width),
                depth: 1,
                ticketWidth: size.width,
                ticketHeight: size.height,
                radius: radius,
                spread: spread,
                expandedStep: step
            )
        }
        var previous = namePoint(0)
        var lowest = previous.y
        for index in 1...20 {
            let point = namePoint(CGFloat(index) / 20)
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            let distance = (dx * dx + dy * dy).squareRoot()
            #expect(distance < 48)
            lowest = min(lowest, point.y)
            previous = point
        }
        #expect(namePoint(1).y < namePoint(0).y)
        #expect(lowest <= namePoint(1).y + 0.5)
    }

    @Test func rightDragLowersFocusAndStaysInRange() {
        let travel = TicketStampBundleLayout.travelPerCard(viewportWidth: 402, count: 8)
        let older = TicketStampBundleLayout.focus(
            start: 5,
            translation: travel,
            travelPerCard: travel,
            count: 8
        )
        let newer = TicketStampBundleLayout.focus(
            start: 5,
            translation: -travel * 2,
            travelPerCard: travel,
            count: 8
        )
        let clamped = TicketStampBundleLayout.focus(
            start: 1,
            translation: 500,
            travelPerCard: travel,
            count: 8
        )
        #expect(older < 5)
        #expect(abs(older - 4) < 0.001)
        #expect(newer > 5)
        #expect(clamped == 0)
        let high = TicketStampBundleLayout.focus(
            start: 6,
            translation: -500,
            travelPerCard: travel,
            count: 8
        )
        #expect(high == 7)
    }

    @Test func liftIsFullOnFocusAndZeroOnNeighbors() {
        #expect(TicketStampBundleLayout.lift(index: 3, focus: 3) == 1)
        #expect(TicketStampBundleLayout.lift(index: 2, focus: 3) == 0)
        #expect(TicketStampBundleLayout.lift(index: 4, focus: 3) == 0)
        #expect(abs(TicketStampBundleLayout.lift(index: 3, focus: 3.25) - 0.75) < 0.001)
    }

    @Test func expandedWidthMatchesHubFaceOnPortraitPhone() {
        let size = TicketStampBundleLayout.expandedTicketSize(hubColumnWidth: 402, usableHeight: 800)
        let hub = TrainLayout.ticketFaceSize(containerWidth: 402)
        #expect(abs(size.width - hub.width) < 0.01)
        #expect(abs(size.width - 370) < 0.01)
        #expect(abs(size.height - hub.height) < 0.01)
    }

    @Test func expandedHeightShrinksOnlyPastTheRatio() {
        let portrait = TicketStampBundleLayout.expandedTicketSize(hubColumnWidth: 402, usableHeight: 800)
        let natural = TrainLayout.ticketFaceSize(containerWidth: 402)
        #expect(abs(portrait.height - natural.height) < 0.01)

        let column = TicketStampBundleLayout.hubColumnWidth(containerWidth: 874, compactHeight: true)
        let landscapeNatural = TrainLayout.ticketFaceSize(containerWidth: column)
        let usable: CGFloat = 360
        let limit = usable * TicketStampBundleLayout.expandedHeightMaxRatio
        #expect(landscapeNatural.height > limit)
        let fitted = TicketStampBundleLayout.expandedTicketSize(
            hubColumnWidth: column,
            usableHeight: usable
        )
        #expect(fitted.height <= limit + 0.5)
        #expect(fitted.height > limit - 1.5)
        #expect(fitted.width < landscapeNatural.width)
    }

    @Test func spreadInterpolatesWidthRadiusPivotAndOriginWithoutAJump() {
        let screen = portraitScreen()
        let count = 8
        var previous = TicketStampBundleLayout.placement(spread: 0, count: count, screen: screen)
        for index in 1...20 {
            let spread = CGFloat(index) / 20
            let place = TicketStampBundleLayout.placement(spread: spread, count: count, screen: screen)
            let widthStep = (place.ticket.width - previous.ticket.width)
            let radiusStep = place.radius - previous.radius
            let pivotStep = place.pivot.x - previous.pivot.x
            let originStep = hypot(
                place.frontOrigin.x - previous.frontOrigin.x,
                place.frontOrigin.y - previous.frontOrigin.y
            )
            #expect(widthStep >= -0.01)
            #expect(radiusStep >= -0.01)
            #expect(pivotStep >= -0.01)
            let widthSpan = TicketStampBundleLayout.placement(spread: 1, count: count, screen: screen).ticket.width
                - TicketStampBundleLayout.placement(spread: 0, count: count, screen: screen).ticket.width
            #expect(widthStep < widthSpan / 20 * 1.35 + 0.5)
            #expect(originStep < 48)
            previous = place
        }
    }

    @Test func openFanKeepsTheFrontCardAndEveryBandInsideTheSafeArea() {
        let screens = [portraitScreen(), landscapeScreen()]
        for screen in screens {
            for count in [2, 5, 8, 20] {
                let place = TicketStampBundleLayout.placement(spread: 1, count: count, screen: screen)
                let front = TicketStampBundleLayout.frontRect(place)
                #expect(contains(screen.safeRect, front, slack: 0.75))
                for index in 0..<count {
                    let mark = TicketStampBundleLayout.markCenter(
                        index: index,
                        count: count,
                        placement: place
                    )
                    #expect(contains(screen.safeRect, mark, slack: 0.75))
                }
                #expect(place.step > 0)
                #expect(place.step <= TicketStampBundleLayout.maxExpandedStepDegrees + 0.01)
            }
        }
    }

    @Test func openFanBottomStaysAboveTheBottomObstacle() {
        var screen = portraitScreen()
        screen.bottomObstacle = 72
        screen.safeBottom = 0
        let place = TicketStampBundleLayout.placement(spread: 1, count: 5, screen: screen)
        let front = TicketStampBundleLayout.frontRect(place)
        let obstacleTop = screen.height - screen.bottomObstacle
        #expect(front.maxY <= obstacleTop - TicketStampBundleLayout.bottomClearance + 0.5)
        #expect(front.minY >= screen.safeTop - 0.5)
        #expect(place.ticket.width > 120)
    }

    @Test func collapsedFanRightEdgeSitsOnTheTrailingMargin() {
        var screen = portraitScreen()
        screen.safeTrailing = 0
        screen.safeBottom = 0
        screen.bottomObstacle = 72
        let place = TicketStampBundleLayout.placement(spread: 0, count: 5, screen: screen)
        let bounds = TicketStampBundleLayout.stackBounds(count: 5, placement: place)
        let bottom = screen.height - screen.bottomObstacle - TicketStampBundleLayout.bottomClearance
        #expect(abs(bounds.maxX - (screen.width - TicketStampBundleLayout.safeMargin)) < 0.5)
        #expect(abs(bounds.maxY - bottom) < 0.5)
    }

    @Test func frontOriginSlidesWithoutAJump() {
        let screen = portraitScreen()
        let start = TicketStampBundleLayout.placement(spread: 0, count: 6, screen: screen).frontOrigin
        let middle = TicketStampBundleLayout.placement(spread: 0.5, count: 6, screen: screen).frontOrigin
        let end = TicketStampBundleLayout.placement(spread: 1, count: 6, screen: screen).frontOrigin
        #expect(abs(middle.x - (start.x + end.x) / 2) < 0.05)
        #expect(abs(middle.y - (start.y + end.y) / 2) < 0.05)
        #expect(start.x > end.x)
    }

    @Test func expandedRadiusUsesTheRatio() {
        let place = TicketStampBundleLayout.placement(spread: 1, count: 4, screen: portraitScreen())
        #expect(abs(place.radius - place.ticket.width * TicketStampBundleLayout.expandedRadiusRatio) < 0.01)
        #expect(place.step <= TicketStampBundleLayout.maxExpandedStepDegrees + 0.01)
    }

    @Test func stackRankKeepsNewerTicketsAboveOlderOnes() {
        let count = 6
        var previous = TicketStampBundleLayout.stackRank(index: 0)
        for index in 1..<count {
            let rank = TicketStampBundleLayout.stackRank(index: index)
            #expect(rank > previous)
            previous = rank
        }
        let newest = TicketStampBundleLayout.stackRank(index: count - 1)
        let oldest = TicketStampBundleLayout.stackRank(index: 0)
        #expect(newest > oldest)
    }

    private func portraitScreen() -> TicketStampBundleLayout.Screen {
        TicketStampBundleLayout.Screen(
            width: 402,
            height: 874,
            safeTop: 59,
            safeLeading: 0,
            safeTrailing: 0,
            safeBottom: 83,
            bottomObstacle: 0,
            hubColumnWidth: 402
        )
    }

    private func landscapeScreen() -> TicketStampBundleLayout.Screen {
        let width: CGFloat = 874
        let column = TicketStampBundleLayout.hubColumnWidth(containerWidth: width, compactHeight: true)
        return TicketStampBundleLayout.Screen(
            width: width,
            height: 402,
            safeTop: 0,
            safeLeading: 59,
            safeTrailing: 59,
            safeBottom: 21,
            bottomObstacle: 0,
            hubColumnWidth: column
        )
    }

    private func contains(_ rect: CGRect, _ point: CGPoint, slack: CGFloat) -> Bool {
        point.x >= rect.minX - slack
            && point.x <= rect.maxX + slack
            && point.y >= rect.minY - slack
            && point.y <= rect.maxY + slack
    }

    private func contains(_ outer: CGRect, _ inner: CGRect, slack: CGFloat) -> Bool {
        inner.minX >= outer.minX - slack
            && inner.minY >= outer.minY - slack
            && inner.maxX <= outer.maxX + slack
            && inner.maxY <= outer.maxY + slack
    }
}
