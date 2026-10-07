//
//  MarsTicketSpec.swift
//  Todo train
//
//  Geometric / color contract for the Mars-style celebration ticket.
//  Physical paper: does not flip with dark mode. No JR monogram replication.
//

import CoreGraphics
import SwiftUI

public enum MarsTicketSpec {
    /// Physical 85 × 57.5 mm.
    public static let aspectWidth: CGFloat = 85
    public static let aspectHeight: CGFloat = 57.5
    public static var aspectRatio: CGFloat { aspectWidth / aspectHeight }

    public static func height(forWidth width: CGFloat) -> CGFloat {
        width * aspectHeight / aspectWidth
    }

    /// Near-square corners — not iOS continuous card radius.
    public static let cornerRadius: CGFloat = 2.5
    public static let cornerRadiusMax: CGFloat = 3

    public static let horizontalMargin: CGFloat = 20
    public static let contentPad: CGFloat = 10
    public static let hubContentPad: CGFloat = 8
    public static let verticalSerialWidth: CGFloat = 14

    // MARK: - Hub Wallet peek deck

    public enum HubStack {
        /// Distance between ticket tops. Larger = airier peeks of covered cards.
        public static let peekStep: CGFloat = 104
        public static let maxVisiblePeeks: Int = Int.max
        public static let horizontalInset: CGFloat = 16
        /// Front (bottom) card is nearly flat; back cards lean a little more.
        public static let tiltNearDegrees: Double = 0.8
        public static let tiltFarDegrees: Double = 5.5
        public static let focusDimOpacity: Double = 0.14
        /// Pick up in place — not a flight to a vanished console.
        public static let liftRise: CGFloat = 22
        public static let liftScale: CGFloat = 1.025
        /// LED 発車看板. Fraction of the Mars face height.
        public static let departSignHeightRatio: CGFloat = 0.44
        public static let departSignGap: CGFloat = 10
        /// Pair under the lifted ticket. Same family as the LED lattice.
        public static let timetablePlateHeightRatio: CGFloat = 0.44
        public static let timetablePlateBottomMargin: CGFloat = 8

        public static func timetablePlateHeight(ticketHeight: CGFloat) -> CGFloat {
            ticketHeight * timetablePlateHeightRatio
        }

        public enum TimetableReveal {
            public static let fillDuration: Double = 0.55
            public static let caretAppearDelay: Double = 0.48
            public static let caretAppearDuration: Double = 0.22
            public static let caretTravelDelay: Double = 0.68
            public static let caretTravelDuration: Double = 0.4
            public static let zoomDelay: Double = 1.15
            public static let zoomDuration: Double = 0.55
        }
        /// Non-focused peers while one ticket is held.
        public static let focusPeerOpacity: Double = 0.55
        /// Lift. Low bounce so the card does not pop through neighbors.
        public static let focus = Animation.smooth(duration: 0.42)
        /// Put-back from a swipe. Critically damped so it seats without chatter.
        public static let putBack = Animation.smooth(duration: 0.5)

        /// Legacy alias — step is the layout contract now (covering creates peeks).
        public static var peekHeight: CGFloat { peekStep }

        public static func peekStep(visibleCount: Int) -> CGFloat {
            _ = visibleCount
            return peekStep
        }
    }

    public enum Density: Equatable, Sendable {
        case celebration
        case hub
    }

    // MARK: - Paper inks (not dark-mode adaptive; print / serial / stamp stay fixed)

    /// Untagged water-cyan stock (ref: docs/references/mars-joshaken.png). Not salmon Edmondson.
    public static let paper = TicketStockColor.untagged.paper.color
    public static let paperBand = TicketStockColor.untagged.band.color
    public static let printInk = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    /// Purple vertical serial ink from the Mars stub edge.
    public static let serialInk = Color(red: 0x7A / 255, green: 0x3D / 255, blue: 0x8A / 255)
    public static let groundPatternOpacity: Double = 0.08
    public static let stampBlue = Color(red: 0.12, green: 0.32, blue: 0.62)
    public static let stampPurple = Color(red: 0.45, green: 0.22, blue: 0.55)

    // MARK: - Type (gothic / default design only — no .rounded)

    /// Destination-scale task title.
    public static let titlePointSize: CGFloat = 22
    /// Fare-scale estimate (yen-sized on a Mars face).
    public static let farePointSize: CGFloat = 28
    public static let fareUnitPointSize: CGFloat = 11
    public static let viaPointSize: CGFloat = 12
    public static let metaPointSize: CGFloat = 11
    public static let validityDayPointSize: CGFloat = 15
    public static let terminalPointSize: CGFloat = 9
    public static let serialPointSize: CGFloat = 9
    public static let stampPointSize: CGFloat = 10

    /// 60-minute printed estimate track (12 × 5 min). Not remaining time.
    public static let durationTrackHeight: CGFloat = 6.5
    public static let durationTrackGap: CGFloat = 1.5
    public static let durationTrackEmptyOpacity: Double = 0.22

    public static func titleFont() -> Font {
        .system(size: titlePointSize, weight: .bold, design: .default)
    }

    public static func fareFont() -> Font {
        .system(size: farePointSize, weight: .bold, design: .default)
    }

    public static func fareUnitFont() -> Font {
        .system(size: fareUnitPointSize, weight: .semibold, design: .default)
    }

    public static func viaFont() -> Font {
        .system(size: viaPointSize, weight: .medium, design: .default)
    }

    public static func metaFont() -> Font {
        .system(size: metaPointSize, weight: .medium, design: .default)
    }

    public static func validityDayFont() -> Font {
        .system(size: validityDayPointSize, weight: .bold, design: .default)
    }

    public static func terminalFont() -> Font {
        .system(size: terminalPointSize, weight: .regular, design: .default)
    }

    public static func serialFont() -> Font {
        .system(size: serialPointSize, weight: .semibold, design: .default)
    }

    public static func stampFont() -> Font {
        .system(size: stampPointSize, weight: .bold, design: .default)
    }

    // MARK: - Issue motion (fixed ms; no reused celebration spring)

    public enum IssueMotion {
        /// Ticket-machine slide out of the slot (90° CW, left edge up).
        public static let ejectMilliseconds = 480
        /// Smooth upright settle after the ticket has cleared the lip.
        public static let uprightMilliseconds = 360
        public static let readableHoldMilliseconds = 1_800
        /// Interrupt: ticket is readable, then zoom — shorter than Hub deck hold.
        public static let interruptZoomHoldMilliseconds = 450
        public static let settleMilliseconds = 300
        /// Full single-issue budget after eject starts.
        public static var presentationMilliseconds: Int {
            ejectMilliseconds + uprightMilliseconds + readableHoldMilliseconds + settleMilliseconds
        }

        /// Clockwise 90°: ticket left edge up / right edge down (as if from a slot).
        public static let slotRotationDegrees: Double = 90

        public static let eject = Animation.easeOut(duration: Double(ejectMilliseconds) / 1_000)
        public static let upright = Animation.easeInOut(duration: Double(uprightMilliseconds) / 1_000)
        public static let settle = Animation.easeIn(duration: Double(settleMilliseconds) / 1_000)
    }

    // MARK: - Arrival: one continuous stamp arc (not tear)

    public enum ArrivalMotion {
        /// Ticket + handle rise together.
        public static let enterMilliseconds = 420
        /// Brief ink readable beat before the same downward exit.
        public static let stampHoldMilliseconds = 320
        public static let exitMilliseconds = 420
        /// Soft residual bob on the handle only (same family as enter).
        public static let nudgeAmplitude: CGFloat = 7

        public static let enter = Animation.easeOut(duration: Double(enterMilliseconds) / 1_000)
        public static let invite = Animation.easeInOut(duration: 0.7)
        public static let slam = Animation.easeOut(duration: 0.14)
        public static let exit = Animation.easeIn(duration: Double(exitMilliseconds) / 1_000)
        public static let arc = Animation.easeOut(duration: 0.2)
    }

    /// Shrink an oversized landing frame around its center; keep Mars aspect.
    public static func clampedLandingRect(_ rect: CGRect, containerSize: CGSize) -> CGRect {
        let inset = HubStack.horizontalInset
        let faceWidth = max(1, containerSize.width - inset * 2)
        let width = min(max(1, rect.width), faceWidth)
        let height = height(forWidth: width)
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

}
