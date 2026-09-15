//
//  MarsTicketSpec.swift
//  Todo train
//
//  Geometric / color contract for the Mars-style celebration ticket.
//  Physical paper: does not flip with dark mode. No JR monogram replication.
//

import CoreGraphics
import SwiftUI

enum MarsTicketSpec {
    /// Physical 85 × 57.5 mm.
    static let aspectWidth: CGFloat = 85
    static let aspectHeight: CGFloat = 57.5
    static var aspectRatio: CGFloat { aspectWidth / aspectHeight }

    static func height(forWidth width: CGFloat) -> CGFloat {
        width * aspectHeight / aspectWidth
    }

    /// Near-square corners — not iOS continuous card radius.
    static let cornerRadius: CGFloat = 2.5
    static let cornerRadiusMax: CGFloat = 3

    static let horizontalMargin: CGFloat = 20
    static let contentPad: CGFloat = 10
    static let hubContentPad: CGFloat = 8
    static let verticalSerialWidth: CGFloat = 14

    // MARK: - Hub Wallet peek deck

    enum HubStack {
        /// Distance between ticket tops. Larger = airier peeks of covered cards.
        static let peekStep: CGFloat = 104
        static let maxVisiblePeeks: Int = Int.max
        static let horizontalInset: CGFloat = 16
        /// Front (bottom) card is nearly flat; back cards lean a little more.
        static let tiltNearDegrees: Double = 0.8
        static let tiltFarDegrees: Double = 5.5
        static let focusDimOpacity: Double = 0.14
        /// Pick up in place — not a flight to a vanished console.
        static let liftRise: CGFloat = 22
        static let liftScale: CGFloat = 1.025
        /// LED 発車看板. Fraction of the Mars face height.
        static let departSignHeightRatio: CGFloat = 0.44
        static let departSignGap: CGFloat = 10
        /// Pair under the lifted ticket. Same family as the LED lattice.
        static let timetablePlateHeightRatio: CGFloat = 0.44
        static let timetablePlateBottomMargin: CGFloat = 8

        static func timetablePlateHeight(ticketHeight: CGFloat) -> CGFloat {
            ticketHeight * timetablePlateHeightRatio
        }

        enum TimetableReveal {
            static let fillDuration: Double = 0.55
            static let caretAppearDelay: Double = 0.48
            static let caretAppearDuration: Double = 0.22
            static let caretTravelDelay: Double = 0.68
            static let caretTravelDuration: Double = 0.4
        }
        /// Non-focused peers while one ticket is held.
        static let focusPeerOpacity: Double = 0.55
        /// Lift. Low bounce so the card does not pop through neighbors.
        static let focus = Animation.smooth(duration: 0.42)
        /// Put-back from a swipe. Critically damped so it seats without chatter.
        static let putBack = Animation.smooth(duration: 0.5)

        /// Legacy alias — step is the layout contract now (covering creates peeks).
        static var peekHeight: CGFloat { peekStep }

        static func peekStep(visibleCount: Int) -> CGFloat {
            _ = visibleCount
            return peekStep
        }
    }

    enum Density: Equatable {
        case celebration
        case hub
    }

    // MARK: - Paper inks (not dark-mode adaptive; print / serial / stamp stay fixed)

    /// Untagged water-cyan stock (ref: docs/references/mars-joshaken.png). Not salmon Edmondson.
    static let paper = TicketStockColor.untagged.paper.color
    static let paperBand = TicketStockColor.untagged.band.color
    static let printInk = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    /// Purple vertical serial ink from the Mars stub edge.
    static let serialInk = Color(red: 0x7A / 255, green: 0x3D / 255, blue: 0x8A / 255)
    static let groundPatternOpacity: Double = 0.08
    static let stampBlue = Color(red: 0.12, green: 0.32, blue: 0.62)
    static let stampPurple = Color(red: 0.45, green: 0.22, blue: 0.55)

    // MARK: - Type (gothic / default design only — no .rounded)

    /// Destination-scale task title.
    static let titlePointSize: CGFloat = 22
    /// Fare-scale estimate (yen-sized on a Mars face).
    static let farePointSize: CGFloat = 28
    static let fareUnitPointSize: CGFloat = 11
    static let viaPointSize: CGFloat = 12
    static let metaPointSize: CGFloat = 11
    static let validityDayPointSize: CGFloat = 15
    static let terminalPointSize: CGFloat = 9
    static let serialPointSize: CGFloat = 9
    static let stampPointSize: CGFloat = 10

    /// 60-minute printed estimate track (12 × 5 min). Not remaining time.
    static let durationTrackHeight: CGFloat = 6.5
    static let durationTrackGap: CGFloat = 1.5
    static let durationTrackEmptyOpacity: Double = 0.22

    static func titleFont() -> Font {
        .system(size: titlePointSize, weight: .bold, design: .default)
    }

    static func fareFont() -> Font {
        .system(size: farePointSize, weight: .bold, design: .default)
    }

    static func fareUnitFont() -> Font {
        .system(size: fareUnitPointSize, weight: .semibold, design: .default)
    }

    static func viaFont() -> Font {
        .system(size: viaPointSize, weight: .medium, design: .default)
    }

    static func metaFont() -> Font {
        .system(size: metaPointSize, weight: .medium, design: .default)
    }

    static func validityDayFont() -> Font {
        .system(size: validityDayPointSize, weight: .bold, design: .default)
    }

    static func terminalFont() -> Font {
        .system(size: terminalPointSize, weight: .regular, design: .default)
    }

    static func serialFont() -> Font {
        .system(size: serialPointSize, weight: .semibold, design: .default)
    }

    static func stampFont() -> Font {
        .system(size: stampPointSize, weight: .bold, design: .default)
    }

    // MARK: - Issue motion (fixed ms; no reused celebration spring)

    enum IssueMotion {
        /// Ticket-machine slide out of the slot (90° CW, left edge up).
        static let ejectMilliseconds = 480
        /// Smooth upright settle after the ticket has cleared the lip.
        static let uprightMilliseconds = 360
        static let readableHoldMilliseconds = 1_800
        /// Interrupt: ticket is readable, then zoom — shorter than Hub deck hold.
        static let interruptZoomHoldMilliseconds = 450
        static let settleMilliseconds = 300
        /// Full single-issue budget after eject starts.
        static var presentationMilliseconds: Int {
            ejectMilliseconds + uprightMilliseconds + readableHoldMilliseconds + settleMilliseconds
        }

        /// Clockwise 90°: ticket left edge up / right edge down (as if from a slot).
        static let slotRotationDegrees: Double = 90

        static let eject = Animation.easeOut(duration: Double(ejectMilliseconds) / 1_000)
        static let upright = Animation.easeInOut(duration: Double(uprightMilliseconds) / 1_000)
        static let settle = Animation.easeIn(duration: Double(settleMilliseconds) / 1_000)
    }

    // MARK: - Arrival: one continuous stamp arc (not tear)

    enum ArrivalMotion {
        /// Ticket + handle rise together.
        static let enterMilliseconds = 420
        /// Brief ink readable beat before the same downward exit.
        static let stampHoldMilliseconds = 320
        static let exitMilliseconds = 420
        /// Soft residual bob on the handle only (same family as enter).
        static let nudgeAmplitude: CGFloat = 7

        static let enter = Animation.easeOut(duration: Double(enterMilliseconds) / 1_000)
        static let invite = Animation.easeInOut(duration: 0.7)
        static let slam = Animation.easeOut(duration: 0.14)
        static let exit = Animation.easeIn(duration: Double(exitMilliseconds) / 1_000)
        static let arc = Animation.easeOut(duration: 0.2)
    }
}
