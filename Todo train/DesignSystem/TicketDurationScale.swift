//
//  TicketDurationScale.swift
//  Todo train
//
//  Printed 60-minute estimate track. Not remaining time, not a streak gauge.
//

import Foundation

enum TicketDurationScale {
    static let cellCount = 12
    static let minutesPerCell = 5
    static var maxMinutes: Int { cellCount * minutesPerCell }

    struct Fill: Equatable, Sendable {
        /// Completely filled 5-minute cells (0…12).
        var fullCells: Int
        /// Partial fill of the next cell (0…1). Zero when minutes is a multiple of 5.
        var lastFraction: Double
    }

    static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 1), maxMinutes)
    }

    /// Position on the 60-minute track (0…1). Same mapping as the printed cells.
    static func unitFraction(minutes: Int) -> Double {
        Double(clampedMinutes(minutes)) / Double(maxMinutes)
    }

    static func filled(minutes: Int) -> Fill {
        filled(exactMinutes: Double(clampedMinutes(minutes)))
    }

    /// Allows 0 so a reveal can grow from an empty track.
    static func filled(exactMinutes: Double) -> Fill {
        let clamped = min(max(exactMinutes, 0), Double(maxMinutes))
        if clamped < 0.000_1 {
            return Fill(fullCells: 0, lastFraction: 0)
        }
        let units = clamped / Double(minutesPerCell)
        let full = min(Int(units), cellCount)
        if full == cellCount {
            return Fill(fullCells: cellCount, lastFraction: 0)
        }
        let fraction = units - Double(full)
        return Fill(fullCells: full, lastFraction: fraction < 0.000_1 ? 0 : fraction)
    }

    static func cellFillAmount(index: Int, fill: Fill) -> Double {
        if index < fill.fullCells { return 1 }
        if index == fill.fullCells { return fill.lastFraction }
        return 0
    }
}
