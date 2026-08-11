//
//  TrainTheme.swift
//  Todo train
//
//  Visual language: 駅の案内板 × 車内乗務
//

import SwiftUI

enum TrainTheme {
    // MARK: - Color tokens

    /// Body / headings on light surfaces.
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.18)

    /// Brand rail navy — primary CTA / in-service.
    static let rail = Color(red: 0.10, green: 0.22, blue: 0.42)

    /// Soft rail for fills.
    static let railSoft = Color(red: 0.10, green: 0.22, blue: 0.42).opacity(0.12)

    /// Arrived / board-ready.
    static let signalGreen = Color(red: 0.18, green: 0.55, blue: 0.38)

    /// Paused / caution.
    static let signalAmber = Color(red: 0.82, green: 0.48, blue: 0.12)

    /// Overtime / abandon.
    static let signalRed = Color(red: 0.78, green: 0.22, blue: 0.20)

    /// Hub / daytime surfaces (cool stone — not cream AI default).
    static let platform = Color(red: 0.93, green: 0.94, blue: 0.95)

    /// Subtle platform wash for section chrome.
    static let platformDeep = Color(red: 0.88, green: 0.90, blue: 0.93)

    /// Focus cabin immersion.
    static let cabin = Color(red: 0.07, green: 0.09, blue: 0.14)

    /// Focus secondary panel.
    static let cabinLift = Color(red: 0.12, green: 0.15, blue: 0.22)

    /// Text on cabin.
    static let cabinInk = Color(red: 0.94, green: 0.95, blue: 0.97)

    /// Muted meta on light.
    static let muted = Color(red: 0.42, green: 0.45, blue: 0.50)

    /// Hairline dividers.
    static let track = Color(red: 0.78, green: 0.80, blue: 0.84)

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
        static let ticket: CGFloat = 12
        static let control: CGFloat = 10
        static let badge: CGFloat = 6
    }

    // MARK: - Motion

    enum Motion {
        static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
        static let soft = Animation.easeInOut(duration: 0.28)
        static let pulse = Animation.easeInOut(duration: 0.55).repeatCount(2, autoreverses: true)
    }

    // MARK: - Type

    enum TypeScale {
        static func screenTitle() -> Font {
            .title3.weight(.semibold)
        }

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
