//
//  ServicePortalHaptics.swift
//  Todo train
//
//  門の触覚。連続で耳障りにしない。Reduce Motion でもホールドの手がかりは残す。
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ServicePortalHaptics {
    static func enter() {
        impact(.heavy, intensity: 0.82)
    }

    static func ignite() {
        impact(.heavy, intensity: 0.94)
    }

    static func occupancyLanded() {
        impact(.light, intensity: 0.48)
    }

    static func readyToPrime() {
        impact(.medium, intensity: 0.80)
    }

    static func primeBegan() {
        impact(.rigid, intensity: 0.78)
    }

    static func primeTick(progress: Double) {
        let intensity = 0.28 + min(max(progress, 0), 1) * 0.50
        impact(.rigid, intensity: intensity)
    }

    static func primeComplete() {
        impact(.rigid, intensity: 1.0)
    }

    private static func impact(_ style: ImpactStyle, intensity: Double) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style.ui)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
        #endif
    }

    private enum ImpactStyle {
        case light, medium, heavy, rigid

        #if canImport(UIKit)
        var ui: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: .light
            case .medium: .medium
            case .heavy: .heavy
            case .rigid: .rigid
            }
        }
        #endif
    }
}
