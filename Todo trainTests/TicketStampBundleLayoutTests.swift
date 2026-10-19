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

    @Test func dragTowardOlderLowersDepth() {
        let still = TicketStampBundleLayout.visualDepth(index: 2, focus: 3, drag: 0)
        let older = TicketStampBundleLayout.visualDepth(index: 2, focus: 3, drag: 72)
        let newer = TicketStampBundleLayout.visualDepth(index: 2, focus: 3, drag: -72)
        #expect(abs(still - 1) < 0.001)
        #expect(abs(older - 0) < 0.001)
        #expect(abs(newer - 2) < 0.001)
    }

    @Test func openFanBottomStaysAboveTheBottomObstacle() {
        let width: CGFloat = 390
        let height: CGFloat = 780
        let obstacle: CGFloat = 72
        let clearance = TicketStampBundleLayout.bottomClearance
        let fan = TicketStampBundleLayout.expandedFan(
            fittingWidth: width,
            fittingHeight: height,
            depth: 4,
            bottomObstacle: obstacle,
            bottomClearance: clearance
        )
        let rect = TicketStampBundleLayout.expandedFanRect(
            fan: fan,
            fittingWidth: width,
            fittingHeight: height,
            depth: 4,
            bottomObstacle: obstacle,
            bottomClearance: clearance
        )
        let obstacleTop = height - obstacle
        let frontBottom = rect.maxY - fan.cornerInset.height
        #expect(rect.maxY <= obstacleTop - clearance + 0.5)
        #expect(frontBottom <= obstacleTop - clearance + 0.5)
        #expect(rect.minY >= -0.5)
        #expect(fan.ticket.width > 120)
    }

    @Test func openFanKeepsTheCornerNearTheBoxCorner() {
        let fan = TicketStampBundleLayout.expandedFan(fittingWidth: 390, fittingHeight: 720, depth: 4)
        #expect(fan.cornerInset.width <= TicketStampBundleLayout.maxCornerInset + 0.5)
        #expect(fan.cornerInset.height <= TicketStampBundleLayout.maxCornerInset + 0.5)
        #expect(fan.ticket.width > 160)
    }

    @Test func openFanFitsASmallPhone() {
        assertFanFits(width: 351, height: 480, depth: TicketStampBundleLayout.depthCap)
    }

    @Test func openFanFitsLandscape() {
        assertFanFits(width: 640, height: 210, depth: TicketStampBundleLayout.depthCap)
    }

    @Test func openFanFitsManyCards() {
        assertFanFits(width: 360, height: 520, depth: 8)
    }

    @Test func expandedRadiusAndStepStayUnderTheCaps() {
        let roomy = TicketStampBundleLayout.expandedFan(fittingWidth: 390, fittingHeight: 720, depth: 4)
        let tight = TicketStampBundleLayout.expandedFan(fittingWidth: 640, fittingHeight: 210, depth: 4)
        #expect(roomy.radius <= roomy.ticket.width * TicketStampBundleLayout.expandedRadiusRatio + 0.01)
        #expect(tight.radius <= tight.ticket.width * TicketStampBundleLayout.expandedRadiusRatio + 0.01)
        #expect(roomy.stepDegrees <= TicketStampBundleLayout.maxExpandedStepDegrees + 0.01)
        #expect(tight.stepDegrees <= TicketStampBundleLayout.maxExpandedStepDegrees + 0.01)
        #expect(openness(tight) <= openness(roomy) + 0.02)
        #expect(openness(roomy) > 0.85)
        let clearance = TicketStampBundleLayout.expandedStepDegrees(
            ticketWidth: roomy.ticket.width,
            ticketHeight: roomy.ticket.height
        )
        #expect(roomy.stepDegrees + 0.6 >= min(clearance, TicketStampBundleLayout.maxExpandedStepDegrees))
    }

    private func openness(_ fan: TicketStampBundleLayout.ExpandedFan) -> CGFloat {
        let minRadius = fan.ticket.width * TicketStampBundleLayout.compactRadiusRatio
        let maxRadius = fan.ticket.width * TicketStampBundleLayout.expandedRadiusRatio
        guard maxRadius - minRadius > 0.001 else { return 0 }
        return (fan.radius - minRadius) / (maxRadius - minRadius)
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

    private func assertFanFits(width: CGFloat, height: CGFloat, depth: Int) {
        let fan = TicketStampBundleLayout.expandedFan(
            fittingWidth: width,
            fittingHeight: height,
            depth: depth
        )
        let rect = TicketStampBundleLayout.expandedFanRect(
            fan: fan,
            fittingWidth: width,
            fittingHeight: height,
            depth: depth
        )
        #expect(rect.minX >= -0.5)
        #expect(rect.minY >= -0.5)
        #expect(rect.maxX <= width + 0.5)
        #expect(rect.maxY <= height + 0.5)
        #expect(fan.ticket.width > 40)
    }
}
