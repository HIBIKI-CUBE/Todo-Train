//
//  CockpitLayoutContract.swift
//  Shared by app + TodoTrainWidget.
//
//  Apple HIG Live Activity sizes (iPhone 15 Pro Max / 430×932):
 //  Lock Screen & expanded DI: 408 × 84…160
 //  Compact leading/trailing: 62.33 × 36.67
 //  Minimal: 36.67…45 × 36.67
 //
 //  StandBy scales the Lock Screen presentation ~200%. Prefer remaining-height
 //  fill over ratio magic; never invent taller than GeometryReader reports.
 //

import CoreGraphics
import Foundation

/// Where a cockpit instrument is rendered.
enum CockpitSurface: Equatable, Sendable {
    case lockScreen
    case standBy
    case islandExpanded
}

/// Density tier chosen from the proposed height.
enum CockpitDensity: Equatable, Sendable {
    /// 120pt+ — full instrument chrome.
    case regular
    /// Below 120pt — drop title / deadline / secondary chrome.
    case compact
}

/// Explicit size contract for Live Activity content.
struct CockpitSizeContract: Equatable, Sendable {
    var width: CGFloat
    var height: CGFloat
    var surface: CockpitSurface

    static let lockScreenMaxHeight: CGFloat = 160
    static let lockScreenMinHeight: CGFloat = 84
    static let proMaxWidth: CGFloat = 408
    static let proWidth: CGFloat = 371
    static let outerMargin: CGFloat = 14
    /// Compact Lock Screen candidates tighten chrome to keep controls inside 84pt.
    static let compactOuterMargin: CGFloat = 8
    static let controlHeight: CGFloat = 44
    static let islandExpandedControlHeight: CGFloat = 40
    static let compactControlHeight: CGFloat = 36
    static let islandCompactSide = CGSize(width: 62.33, height: 36.67)
    static let islandMinimalMin = CGSize(width: 36.67, height: 36.67)
    static let islandMinimalMaxWidth: CGFloat = 45
    static let islandExpandedTrailingMaxWidth: CGFloat = 64

    var density: CockpitDensity {
        CockpitLayoutPolicy.density(forHeight: height)
    }

    var contentWidth: CGFloat {
        max(0, width - Self.outerMargin * 2)
    }

    var contentHeight: CGFloat {
        max(0, height - Self.outerMargin * 2)
    }

    /// StandBy instrument pane share (left).
    var standByInstrumentFraction: CGFloat { 0.68 }

    var standByControlFraction: CGFloat { 1 - standByInstrumentFraction }

    static func lockScreen(width: CGFloat = proMaxWidth, height: CGFloat = lockScreenMaxHeight) -> CockpitSizeContract {
        CockpitSizeContract(
            width: width,
            height: min(max(height, lockScreenMinHeight), lockScreenMaxHeight),
            surface: .lockScreen
        )
    }

    /// StandBy keeps the real proposal height (floor only).
    static func standBy(width: CGFloat = proMaxWidth, height: CGFloat = lockScreenMaxHeight) -> CockpitSizeContract {
        CockpitSizeContract(
            width: width,
            height: max(height, lockScreenMinHeight),
            surface: .standBy
        )
    }

    static func islandExpanded(width: CGFloat = proMaxWidth, height: CGFloat = lockScreenMaxHeight) -> CockpitSizeContract {
        CockpitSizeContract(
            width: width,
            height: min(max(height, lockScreenMinHeight), lockScreenMaxHeight),
            surface: .islandExpanded
        )
    }
}

/// Fixed chrome for StandBy remaining-height fill (no ratio magic).
struct CockpitStandByChrome: Equatable, Sendable {
    static let margin: CGFloat = 8
    static let progressHeight: CGFloat = 6
    static let titleRowHeight: CGFloat = 20
    static let deadlineRowHeight: CGFloat = 16
    static let minTimerHeight: CGFloat = 36
    static let titleFont: CGFloat = 15
    static let badgeFont: CGFloat = 14
    static let deadlineFont: CGFloat = 12
    static let controlFont: CGFloat = 18
    static let controlIcon: CGFloat = 22
}

/// StandBy layout context passed through the environment.
struct CockpitStandByMetrics: Equatable, Sendable {
    var width: CGFloat
    var height: CGFloat

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = max(height, CockpitSizeContract.lockScreenMinHeight)
    }

    var density: CockpitDensity {
        CockpitLayoutPolicy.density(forHeight: height)
    }

    var margin: CGFloat { CockpitStandByChrome.margin }
    var progressHeight: CGFloat { CockpitStandByChrome.progressHeight }
    var titleSize: CGFloat { CockpitStandByChrome.titleFont }
    var badgeSize: CGFloat { CockpitStandByChrome.badgeFont }
    var deadlineSize: CGFloat { CockpitStandByChrome.deadlineFont }
    var controlFontSize: CGFloat { CockpitStandByChrome.controlFont }
    var controlIconSize: CGFloat { CockpitStandByChrome.controlIcon }
    /// Soft upper bound for timer autofit (actual size comes from remaining frame).
    var timerSize: CGFloat { max(CockpitStandByChrome.minTimerHeight, height * 0.9) }
}

enum CockpitLayoutPolicy {
    static func density(forHeight height: CGFloat) -> CockpitDensity {
        height >= 120 ? .regular : .compact
    }

    /// Hidden width template for compact `Text(timerInterval:)` (max digit shape).
    static func islandTimerWidthTemplate(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        if total >= 3600 { return "0:00:00" }
        if total >= 10 * 60 { return "00:00" }
        return "0:00"
    }

    /// Fixed vertical budget for Lock Screen / StandBy instrument stacks.
    static func fits(
        proposedHeight: CGFloat,
        density: CockpitDensity,
        hasControls: Bool,
        surface: CockpitSurface
    ) -> Bool {
        let required = requiredTotalHeight(
            density: density,
            hasControls: hasControls,
            surface: surface,
            proposedHeight: proposedHeight
        )
        return required <= proposedHeight + 0.5
    }

    static func requiredTotalHeight(
        density: CockpitDensity,
        hasControls: Bool,
        surface: CockpitSurface,
        proposedHeight: CGFloat? = nil
    ) -> CGFloat {
        switch surface {
        case .standBy:
            return standByFixedChromeHeight(density: density) + CockpitStandByChrome.margin * 2
        case .lockScreen, .islandExpanded:
            return lockScreenTotalHeight(density: density, hasControls: hasControls)
        }
    }

    static func lockScreenTotalHeight(density: CockpitDensity, hasControls: Bool) -> CGFloat {
        switch density {
        case .regular:
            let margin = CockpitSizeContract.outerMargin * 2
            let base: CGFloat = 40 + 4 + 18 + 6 + 4 + 2 + 12
            let controls = hasControls ? (6 + CockpitSizeContract.controlHeight) : 0
            return margin + base + controls
        case .compact:
            let margin = CockpitSizeContract.compactOuterMargin * 2
            let timer: CGFloat = 28
            if hasControls {
                return margin + timer + 4 + CockpitSizeContract.compactControlHeight
            }
            return margin + timer + 4 + 3
        }
    }

    static func lockScreenRegularWithoutDeadlineHeight(hasControls: Bool) -> CGFloat {
        let margin = CockpitSizeContract.outerMargin * 2
        let base: CGFloat = 40 + 4 + 18 + 6 + 4
        let controls = hasControls ? (6 + CockpitSizeContract.controlHeight) : 0
        return margin + base + controls
    }

    /// Fixed chrome + minimum timer (timer then fills any remainder).
    static func standByFixedChromeHeight(density: CockpitDensity) -> CGFloat {
        switch density {
        case .regular:
            return CockpitStandByChrome.titleRowHeight
                + 4
                + CockpitStandByChrome.minTimerHeight
                + 4
                + CockpitStandByChrome.progressHeight
                + 4
                + CockpitStandByChrome.deadlineRowHeight
        case .compact:
            return CockpitStandByChrome.minTimerHeight
                + 4
                + CockpitStandByChrome.progressHeight
        }
    }

    static func standByInstrumentHeight(density: CockpitDensity) -> CGFloat {
        standByFixedChromeHeight(density: density)
    }

    static func resolvedDensity(
        proposedHeight: CGFloat,
        hasControls: Bool,
        surface: CockpitSurface
    ) -> CockpitDensity {
        if surface == .standBy {
            return density(forHeight: proposedHeight)
        }
        if fits(proposedHeight: proposedHeight, density: .regular, hasControls: hasControls, surface: surface) {
            return .regular
        }
        if hasControls,
           surface == .lockScreen || surface == .islandExpanded,
           lockScreenRegularWithoutDeadlineHeight(hasControls: true) <= proposedHeight + 0.5 {
            return .regular
        }
        return .compact
    }
}
