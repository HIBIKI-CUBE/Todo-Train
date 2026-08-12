//
//  TrainTheme.swift
//  Todo train
//
//  Visual language: Apple HIG first, train metaphor as accent.
//

import SwiftUI
import UIKit

enum TrainTheme {
    // MARK: - Semantic (adaptive)

    /// Body / headings — follows light & dark.
    static let ink = Color.primary

    /// Meta / secondary copy.
    static let muted = Color.secondary

    /// Grouped list canvas.
    static let platform = Color(uiColor: .systemGroupedBackground)

    /// Elevated row / secondary grouped fill.
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    /// Separators.
    static let track = Color(uiColor: .separator)

    // MARK: - Brand & signals (tuned for both appearances)

    /// Brand rail navy — primary CTA / in-service.
    static let rail = Color("AccentColor")

    /// Soft rail for fills (adaptive via opacity on secondary fill).
    static let railSoft = Color("AccentColor").opacity(0.14)

    /// Arrived / board-ready.
    static let signalGreen = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.78, blue: 0.52, alpha: 1)
            : UIColor(red: 0.18, green: 0.55, blue: 0.38, alpha: 1)
    })

    /// Paused / caution.
    static let signalAmber = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 1)
            : UIColor(red: 0.82, green: 0.48, blue: 0.12, alpha: 1)
    })

    /// Overtime / abandon.
    static let signalRed = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.42, blue: 0.40, alpha: 1)
            : UIColor(red: 0.78, green: 0.22, blue: 0.20, alpha: 1)
    })

    // MARK: - Focus cabin (always immersive; independent of system appearance)

    static let cabin = Color(red: 0.07, green: 0.09, blue: 0.14)
    static let cabinLift = Color(red: 0.14, green: 0.17, blue: 0.24)
    static let cabinInk = Color(red: 0.95, green: 0.96, blue: 0.98)

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let control: CGFloat = 10
        static let badge: CGFloat = 6
    }

    // MARK: - Motion

    enum Motion {
        static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
        static let soft = Animation.easeInOut(duration: 0.28)
        static let pulse = Animation.easeInOut(duration: 0.55).repeatCount(2, autoreverses: true)
        /// Issued ticket bloom (snappy micro-interaction; keep under ~0.3s perceptual).
        static let issueEject = Animation.spring(response: 0.24, dampingFraction: 0.86)
        /// Gauge settle / detent escape (“ビュン”).
        static let gaugeSnap = Animation.spring(response: 0.22, dampingFraction: 0.62)
    }

    // MARK: - Type

    enum TypeScale {
        static func ticketTitle() -> Font {
            .body.weight(.semibold)
        }

        static func meta() -> Font {
            .caption.weight(.medium)
        }

        static func status() -> Font {
            .subheadline.weight(.semibold)
        }

        static func timer(size: CGFloat = 72) -> Font {
            .system(size: size, weight: .light, design: .rounded)
        }

        static func timerMeta() -> Font {
            .subheadline.weight(.medium)
        }
    }
}
