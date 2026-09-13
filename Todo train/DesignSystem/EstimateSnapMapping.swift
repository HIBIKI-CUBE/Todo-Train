//
//  EstimateSnapMapping.swift
//  Todo train
//
//  Linear minutes ↔ fraction mapping with sticky detent scrub.
//  Visual position and finger X share the same model (no equal-width hit zones).
//

import Foundation
import CoreGraphics

enum EstimateSnapMapping {
    static let stops = EstimateChips.ticketPresets
    static let maxMinutes = 60

    /// Rubber-band extent beyond 0…1 (as fraction of track).
    static let rubberLimit: CGFloat = 0.18

    /// Progress toward the adjacent stop required to escape the sticky well (0…1 of the gap).
    /// Above 0.5 = hysteresis past the midpoint.
    static let stickyEscapeProgress: CGFloat = 0.62

    /// How much the knob follows the finger while still stuck to the anchor (0 = glued, 1 = free).
    static let stickyStretch: CGFloat = 0.38

    struct StickyScrub: Equatable {
        var displayFraction: CGFloat
        var anchoredMinutes: Int
        /// True when the finger escaped the well and landed on a new stop.
        var didEscape: Bool
    }

    /// 0...1 from minutes (clamped). 30 → 0.5, 60 → 1.
    static func fraction(minutes: Int) -> CGFloat {
        let clamped = min(max(minutes, 0), maxMinutes)
        return CGFloat(clamped) / CGFloat(maxMinutes)
    }

    /// Raw minutes from a 0...1 fraction (before snap).
    static func rawMinutes(fraction: CGFloat) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return Double(clamped) * Double(maxMinutes)
    }

    /// Nearest stop; ties prefer the lower preset (matches EstimateHeuristic).
    static func snap(rawMinutes: Double) -> Int {
        stops.min(by: { lhs, rhs in
            let dL = abs(Double(lhs) - rawMinutes)
            let dR = abs(Double(rhs) - rawMinutes)
            if dL == dR { return lhs < rhs }
            return dL < dR
        }) ?? EstimateHeuristic.defaultHighlightMinutes
    }

    static func snap(fraction: CGFloat) -> Int {
        snap(rawMinutes: rawMinutes(fraction: fraction))
    }

    /// Fraction from an X position within a track width (clamped 0…1).
    static func fraction(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1)
    }

    /// Unclamped finger fraction (may be <0 or >1).
    static func unboundedFraction(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return x / width
    }

    static func snap(x: CGFloat, width: CGFloat) -> Int {
        snap(fraction: fraction(x: x, width: width))
    }

    /// Classic rubber-band: past 0…1, displacement decays.
    static func rubberBand(_ fraction: CGFloat, limit: CGFloat = rubberLimit) -> CGFloat {
        if fraction >= 0, fraction <= 1 { return fraction }
        let dimension: CGFloat = 1
        if fraction < 0 {
            let overflow = -fraction
            let damped = (overflow * dimension * limit) / (dimension + limit * overflow)
            return -damped
        } else {
            let overflow = fraction - 1
            let damped = (overflow * dimension * limit) / (dimension + limit * overflow)
            return 1 + damped
        }
    }

    /// Stop implied by a (possibly unclamped) finger fraction.
    static func stop(forFingerFraction fingerFraction: CGFloat) -> Int {
        let clamped = min(max(fingerFraction, 0), 1)
        return snap(fraction: clamped)
    }

    /// Sticky detent scrub: stretch away from `anchoredMinutes`, escape only past hysteresis.
    static func stickyScrub(
        fingerFraction: CGFloat,
        anchoredMinutes: Int
    ) -> StickyScrub {
        let finger = rubberBand(fingerFraction)
        let anchor = resolvedAnchor(anchoredMinutes)
        let anchorF = fraction(minutes: anchor)
        guard let index = stops.firstIndex(of: anchor) else {
            return StickyScrub(displayFraction: anchorF, anchoredMinutes: anchor, didEscape: false)
        }

        if finger > anchorF, index + 1 < stops.count {
            let next = stops[index + 1]
            let nextF = fraction(minutes: next)
            let gap = nextF - anchorF
            guard gap > 0 else {
                return StickyScrub(displayFraction: anchorF, anchoredMinutes: anchor, didEscape: false)
            }
            let progress = (finger - anchorF) / gap
            if progress >= stickyEscapeProgress {
                return StickyScrub(displayFraction: nextF, anchoredMinutes: next, didEscape: true)
            }
            let display = anchorF + gap * progress * stickyStretch
            return StickyScrub(displayFraction: display, anchoredMinutes: anchor, didEscape: false)
        }

        if finger < anchorF, index > 0 {
            let prev = stops[index - 1]
            let prevF = fraction(minutes: prev)
            let gap = anchorF - prevF
            guard gap > 0 else {
                return StickyScrub(displayFraction: anchorF, anchoredMinutes: anchor, didEscape: false)
            }
            let progress = (anchorF - finger) / gap
            if progress >= stickyEscapeProgress {
                return StickyScrub(displayFraction: prevF, anchoredMinutes: prev, didEscape: true)
            }
            let display = anchorF - gap * progress * stickyStretch
            return StickyScrub(displayFraction: display, anchoredMinutes: anchor, didEscape: false)
        }

        // Overshoot past ends while still anchored, or tiny drift.
        if finger < 0 || finger > 1 {
            return StickyScrub(displayFraction: finger, anchoredMinutes: anchor, didEscape: false)
        }
        let display = anchorF + (finger - anchorF) * stickyStretch
        return StickyScrub(displayFraction: display, anchoredMinutes: anchor, didEscape: false)
    }

    private static func resolvedAnchor(_ minutes: Int) -> Int {
        if stops.contains(minutes) { return minutes }
        return snap(rawMinutes: Double(minutes))
    }
}
