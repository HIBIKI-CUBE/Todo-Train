//
//  TrainChrome.swift
//  Todo train
//

import SwiftUI

// MARK: - Focus cabin (immersive; not used on Hub / History)

struct CabinBackground: View {
    var phase: FocusTimerPhase = .cruise
    var reduceTransparency: Bool = false

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                if !reduceTransparency {
                    Rectangle()
                        .fill(statusWash)
                        .ignoresSafeArea()
                }
            }
    }

    private var statusWash: Color {
        switch phase {
        case .cruise:
            return .clear
        case .approach:
            return TrainTheme.signalAmber.opacity(0.05)
        case .final:
            return TrainTheme.signalAmber.opacity(0.10)
        case .overtime:
            return TrainTheme.signalRed.opacity(0.12)
        }
    }
}

/// Dense instrument panel chrome — hairline grid, no card chrome.
enum FocusPanel {
    static let hairline = Color.white.opacity(0.14)
    static let fill = Color.white.opacity(0.04)
    static let fillRaised = Color.white.opacity(0.07)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.55)
    static let dim = Color.white.opacity(0.35)

    static let hairlineWidth: CGFloat = 1
}

struct FocusProgressBar: View {
    let progress: Double
    let phase: FocusTimerPhase

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(phase.accentColor)
                    .frame(width: max(proxy.size.width * clampedProgress, progress > 0 ? 2 : 0))
                if phase == .overtime, progress > 1 {
                    Rectangle()
                        .fill(TrainTheme.signalRed.opacity(0.45))
                        .frame(width: 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("進捗")
        .accessibilityValue("\(Int(clampedProgress * 100))パーセント")
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

// MARK: - Focus control bank (gapless panel grid)

struct FocusControlBank<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FocusControlDivider: View {
    var body: some View {
        Rectangle()
            .fill(FocusPanel.hairline)
            .frame(height: FocusPanel.hairlineWidth)
    }
}

struct FocusControlVerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(FocusPanel.hairline)
            .frame(width: FocusPanel.hairlineWidth)
    }
}

struct FocusControlCellStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill.opacity(configuration.isPressed ? 0.78 : 1))
            .contentShape(Rectangle())
            .animation(TrainTheme.Motion.spring, value: configuration.isPressed)
    }
}

// MARK: - Focus controls (cabin-only; legacy sheet styles)

struct FocusPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.black)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .fill(TrainTheme.signalGreen)
            )
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(TrainTheme.Motion.spring, value: configuration.isPressed)
    }
}

struct FocusSecondaryButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(TrainTheme.Motion.spring, value: configuration.isPressed)
    }
}
