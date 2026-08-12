//
//  TrainChrome.swift
//  Todo train
//

import SwiftUI

// MARK: - Focus cabin (immersive; not used on Hub / History)

struct CabinBackground: View {
    var overtime: Bool = false
    var reduceTransparency: Bool = false

    var body: some View {
        ZStack {
            TrainTheme.cabin
            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        (overtime ? TrainTheme.signalRed : TrainTheme.rail).opacity(0.22),
                        .clear
                    ],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Badges

struct SignalBadge: View {
    enum Kind {
        case inService
        case outOfService
        case paused
        case overtime
        case arrived
        case abandoned
        case due

        var label: String {
            switch self {
            case .inService: "運行中"
            case .outOfService: "運休"
            case .paused: "停車中"
            case .overtime: "超過"
            case .arrived: "到着"
            case .abandoned: "放棄"
            case .due: "期限"
            }
        }

        var color: Color {
            switch self {
            case .inService, .arrived: TrainTheme.signalGreen
            case .outOfService: TrainTheme.muted
            case .paused, .due: TrainTheme.signalAmber
            case .overtime, .abandoned: TrainTheme.signalRed
            }
        }
    }

    let kind: Kind
    var customLabel: String?

    var body: some View {
        Text(customLabel ?? kind.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(kind.color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Focus controls (cabin-only)

struct FocusPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(TrainTheme.cabin)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .fill(TrainTheme.signalGreen)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(TrainTheme.Motion.spring, value: configuration.isPressed)
    }
}

struct FocusSecondaryButtonStyle: ButtonStyle {
    var tint: Color = TrainTheme.cabinInk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .fill(TrainTheme.cabinLift.opacity(0.9))
            )
            .overlay {
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(TrainTheme.Motion.spring, value: configuration.isPressed)
    }
}
