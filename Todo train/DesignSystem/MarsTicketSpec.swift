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

    // MARK: - Hub Wallet stack

    enum HubStack {
        /// Visible strip height for non-front tickets (title + minutes peek).
        static let peekHeight: CGFloat = 52
        /// Overlap so the stack reads as one deck.
        static let peekOverlap: CGFloat = 10
        static let maxVisiblePeeks: Int = 8
        static let frontBoardBarHeight: CGFloat = 48
        static let horizontalInset: CGFloat = 16
        static let bringToFront = Animation.spring(response: 0.38, dampingFraction: 0.86)

        static func peekStep(visibleCount: Int) -> CGFloat {
            max(0, peekHeight - peekOverlap)
        }

        /// Total height of a stack with `count` tickets (front full + peeks behind).
        static func stackHeight(ticketWidth: CGFloat, count: Int, frontExpanded: Bool) -> CGFloat {
            guard count > 0 else { return 0 }
            let frontH = height(forWidth: ticketWidth) + (frontExpanded ? frontBoardBarHeight : 0)
            let behind = max(0, min(count, maxVisiblePeeks) - 1)
            return frontH + CGFloat(behind) * peekStep(visibleCount: behind)
        }
    }

    enum Density: Equatable {
        case celebration
        case hub
    }

    // MARK: - Fixed paper inks (never semantic / adaptive)

    /// Water-cyan stock (ref: docs/references/mars-joshaken.png). Not salmon Edmondson.
    static let paper = Color(red: 0xD5 / 255, green: 0xE6 / 255, blue: 0xEA / 255)
    static let paperBand = Color(red: 0xE7 / 255, green: 0xF1 / 255, blue: 0xF3 / 255)
    static let printInk = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    /// Purple vertical serial ink from the Mars stub edge.
    static let serialInk = Color(red: 0x7A / 255, green: 0x3D / 255, blue: 0x8A / 255)
    static let groundPatternOpacity: Double = 0.08
    static let stampBlue = Color(red: 0.12, green: 0.32, blue: 0.62)
    static let stampPurple = Color(red: 0.45, green: 0.22, blue: 0.55)

    // MARK: - Type (gothic / default design only — no .rounded)

    static func kindFont() -> Font {
        .system(size: 11, weight: .semibold, design: .default)
    }

    static func titleFont() -> Font {
        .system(size: 24, weight: .bold, design: .default)
    }

    static func viaFont() -> Font {
        .system(size: 12, weight: .medium, design: .default)
    }

    static func metaFont() -> Font {
        .system(size: 11, weight: .medium, design: .default)
    }

    static func terminalFont() -> Font {
        .system(size: 9, weight: .regular, design: .default)
    }

    static func serialFont() -> Font {
        .system(size: 9, weight: .semibold, design: .default)
    }

    static func stampFont() -> Font {
        .system(size: 10, weight: .bold, design: .default)
    }

    // MARK: - Issue motion (fixed ms; no reused celebration spring)

    enum IssueMotion {
        /// Ticket-machine slide out of the slot (90° CW, left edge up).
        static let ejectMilliseconds = 480
        /// Smooth upright settle after the ticket has cleared the lip.
        static let uprightMilliseconds = 360
        static let readableHoldMilliseconds = 1_800
        static let settleMilliseconds = 300
        /// Full single-issue budget after eject starts.
        static var presentationMilliseconds: Int {
            ejectMilliseconds + 90 + uprightMilliseconds + readableHoldMilliseconds + settleMilliseconds
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
