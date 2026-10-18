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
    @Test func offsetRaisesOlderTicketsAndFollowsOnlyTheFront() {
        let raised = TicketStampBundleLayout.offset(depth: 2, ticketHeight: 200, drag: 50)
        #expect(raised.width == 0)
        #expect(raised.height == -0.45 * 200 * 2)

        let front = TicketStampBundleLayout.offset(depth: 0, ticketHeight: 200, drag: 50)
        #expect(front.width == 50 * 0.28)
        #expect(front.height == 0)

        let flung = TicketStampBundleLayout.offset(depth: 0, ticketHeight: 200, drag: 400)
        #expect(flung.width == TicketStampBundleLayout.dragFollowLimit)
        let flungLeft = TicketStampBundleLayout.offset(depth: 0, ticketHeight: 200, drag: -400)
        #expect(flungLeft.width == -TicketStampBundleLayout.dragFollowLimit)
    }

    @Test func bandHeightUsesPeekRatio() {
        #expect(TicketStampBundleLayout.bandHeight(ticketHeight: 110, depth: 2) == 110 * (1 + 0.45 * 2))
        let historyWidth = TicketStampBundleLayout.historyTicketWidth
        let historyVisual = MarsTicketSpec.height(forWidth: TicketStampBundleLayout.baseWidth)
            * (historyWidth / TicketStampBundleLayout.baseWidth)
        #expect(abs(historyVisual - TicketStampBundleLayout.historyTicketHeight) < 0.01)
        #expect(TicketStampBundleLayout.bandHeight(ticketHeight: 100, depth: 0) == 100)
        #expect(TicketStampBundleLayout.bandHeight(ticketHeight: 80, depth: 4) == 80 * (1 + 0.45 * 4))
    }

    @Test func fanDepthIsLowerOnTheHistoryStrip() {
        #expect(TicketStampBundleLayout.maxFanDepth(for: .historyStrip) == 2)
        #expect(TicketStampBundleLayout.maxFanDepth(for: .shutdown) == 4)
        #expect(TicketStampBundleLayout.maxFanDepth(for: .viewer) == 4)
        #expect(TicketStampBundleLayout.stackDepth(stampCount: 5, focusIndex: 4, style: .historyStrip) == 2)
        #expect(TicketStampBundleLayout.stackDepth(stampCount: 5, focusIndex: 4, style: .shutdown) == 4)
        #expect(TicketStampBundleLayout.stackDepth(stampCount: 5, focusIndex: 0, style: .shutdown) == 0)
        #expect(TicketStampBundleLayout.stackDepth(stampCount: 0, focusIndex: 3, style: .viewer) == 0)
    }

    @Test func fittedTicketShrinksSoTheStackStaysInTheViewport() {
        let wide = TicketStampBundleLayout.fittedTicketSize(
            targetWidth: 300,
            viewportHeight: 10_000,
            depth: 4
        )
        let natural = MarsTicketSpec.height(forWidth: 300)
        #expect(abs(wide.height - natural) < 0.01)
        #expect(abs(wide.width - 300) < 0.01)

        let tight = TicketStampBundleLayout.fittedTicketSize(
            targetWidth: 300,
            viewportHeight: 200,
            depth: 4
        )
        let expected = (200 - 10) / (1 + 0.45 * 4)
        #expect(abs(tight.height - expected) < 0.01)
        let expectedWidth = expected * MarsTicketSpec.aspectWidth / MarsTicketSpec.aspectHeight
        #expect(abs(tight.width - expectedWidth) < 0.01)
        let band = TicketStampBundleLayout.bandHeight(ticketHeight: tight.height, depth: 4)
        #expect(band <= 200 - 10 + 0.01)
    }

    @Test func shutdownBandHeightMatchesTheLayout() {
        let band = TicketStampBundleDeckView.shutdownBandHeight(
            containerWidth: 390,
            bandViewportHeight: 280,
            depth: 4
        )
        let target = TicketStampBundleLayout.shutdownTargetWidth(containerWidth: 390)
        let ticket = TicketStampBundleLayout.fittedTicketSize(
            targetWidth: target,
            viewportHeight: 280,
            depth: 4
        )
        let expected = TicketStampBundleLayout.bandHeight(ticketHeight: ticket.height, depth: 4)
        #expect(abs(band - expected) < 0.01)
        #expect(band <= 280)
    }

    @Test func cornerSealBoundsStayInsideThePeekAtSixDegrees() {
        let width: CGFloat = 300
        let height = MarsTicketSpec.height(forWidth: width)
        let bounds = TicketStampBundleLayout.cornerSealBounds(
            ticketWidth: width,
            ticketHeight: height,
            rotationDegrees: -6
        )
        #expect(bounds.maxY < height * TicketStampBundleLayout.peekRatio)
        #expect(bounds.minY > 0)

        let shipped = TicketStampBundleLayout.cornerSealBounds(
            ticketWidth: width,
            ticketHeight: height,
            rotationDegrees: TicketStampBundleLayout.cornerSealRotationDegrees
        )
        #expect(shipped.maxY < height * TicketStampBundleLayout.peekRatio)

        let metrics = FukeiSealLayout.metrics(luxury: 1)
        let side = min(width, height) * TicketStampBundleLayout.cornerSealSideRatio
        let sealTop = height * TicketStampBundleLayout.cornerSealCenterYRatio - side / 2
        let frameOrigin = (1 - metrics.frameSide) / 2 * side
        let titleBottom = frameOrigin + (metrics.textBlockTop + metrics.titleSize) * side
        #expect(sealTop + titleBottom < height * TicketStampBundleLayout.peekRatio)
    }
}
