//
//  SystemStrip.swift
//  Todo train
//
//  CHK の灯と PHONE の窓。丸灯と刻印の地は格子が描く。
//  窓の字は参照モックの最終 CSS。
//

import SwiftUI
import UIKit

enum OpeningPanelLampStyle: Equatable {
    case off
    case green
    case amber
    case yellow

    var fill: Color {
        switch self {
        case .off:
            return OpeningPanelTokens.Palette.lampOff
        case .green:
            return OpeningPanelTokens.Palette.lampGreen
        case .amber:
            return OpeningPanelTokens.Palette.amber
        case .yellow:
            return OpeningPanelTokens.Palette.fault
        }
    }

    /// `.sl.on` と `.sl.amb` の `box-shadow: 0 0 3px`。黄は影なし。
    var glow: Color {
        switch self {
        case .green:
            return Color(red: 132 / 255, green: 196 / 255, blue: 128 / 255, opacity: 0.3)
        case .amber:
            return Color(red: 1, green: 176 / 255, blue: 0, opacity: 0.3)
        case .off, .yellow:
            return .clear
        }
    }

    var spoken: String {
        switch self {
        case .off: "消灯"
        case .green: "点灯"
        case .amber: "琥珀"
        case .yellow: "黄"
        }
    }
}

struct OpeningPanelLampField: Equatable {
    var master: OpeningPanelLampStyle = .off
    var clock: OpeningPanelLampStyle = .off
    var timetable: OpeningPanelLampStyle = .off
    var tickets: OpeningPanelLampStyle = .off
    var ext: OpeningPanelLampStyle = .off
    var awake: OpeningPanelLampStyle = .off
    var relay: OpeningPanelLampStyle = .off
    var mac: OpeningPanelLampStyle = .off
}

enum OpeningPanelPhoneSupply: Equatable {
    case unknown
    case unplugged(percent: Int)
    case charging
    case full

    var onExternalPower: Bool {
        switch self {
        case .charging, .full:
            return true
        case .unknown, .unplugged:
            return false
        }
    }

    var batteryState: UIDevice.BatteryState {
        switch self {
        case .unknown: .unknown
        case .unplugged: .unplugged
        case .charging: .charging
        case .full: .full
        }
    }
}

enum OpeningPanelSystem {
    /// 盤が見えていて、電気が来ているあいだだけ電池を読む。
    static func monitorsBattery(panelVisible: Bool, powered: Bool) -> Bool {
        panelVisible && powered
    }

    static func checkLamp(powered: Bool, lit: Bool) -> OpeningPanelLampStyle {
        powered && lit ? .green : .off
    }

    static func phoneSupply(state: UIDevice.BatteryState, level: Float) -> OpeningPanelPhoneSupply {
        switch state {
        case .charging:
            return .charging
        case .full:
            return .full
        case .unplugged:
            guard level >= 0 else { return .unknown }
            let percent = min(100, max(0, Int((Double(level) * 100).rounded())))
            return .unplugged(percent: percent)
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

enum OpeningPanelPhone {
    struct Reading: Equatable {
        var text: String
        var extLit: Bool
        var awakeLit: Bool

        static let hidden = Reading(text: "", extLit: false, awakeLit: false)
    }

    /// `#devW`。10px、右寄せ、琥珀。
    enum Metrics {
        static let fontSize: CGFloat = 10
        static let horizontalPadding: CGFloat = 3
    }

    static func reading(
        powered: Bool,
        supply: OpeningPanelPhoneSupply,
        keepAwake: Bool
    ) -> Reading {
        guard powered else { return .hidden }
        let awake = FocusIdleTimerPolicy.shouldDisableIdleTimer(
            settingEnabled: keepAwake,
            batteryState: supply.batteryState
        )
        switch supply {
        case .unknown:
            return Reading(text: "----", extLit: false, awakeLit: false)
        case .full:
            return Reading(text: "FULL", extLit: true, awakeLit: awake)
        case .charging:
            return Reading(text: "CHG", extLit: true, awakeLit: awake)
        case .unplugged(let percent):
            let text = percent <= 20 ? "LO \(percent)%" : "\(percent)%"
            return Reading(text: text, extLit: false, awakeLit: false)
        }
    }
}

/// PHONE の窓。監視そのものは盤が持つ。
struct OpeningPanelPhoneWindow: View {
    var reading: OpeningPanelPhone.Reading
    var powered: Bool

    var body: some View {
        Text(reading.text)
            .font(.system(size: OpeningPanelPhone.Metrics.fontSize))
            .monospacedDigit()
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, OpeningPanelPhone.Metrics.horizontalPadding)
            .opacity(powered ? 1 : 0)
            .accessibilityLabel(reading.text)
            .accessibilityHidden(!powered || reading.text.isEmpty)
    }
}
