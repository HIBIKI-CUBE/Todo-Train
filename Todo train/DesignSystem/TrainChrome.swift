//
//  TrainChrome.swift
//  Todo train
//

import SwiftUI

// MARK: - Backgrounds

struct PlatformBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                TrainTheme.platform,
                TrainTheme.platformDeep.opacity(0.85),
                TrainTheme.platform
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct CabinBackground: View {
    var overtime: Bool = false

    var body: some View {
        ZStack {
            TrainTheme.cabin
            RadialGradient(
                colors: [
                    (overtime ? TrainTheme.signalRed : TrainTheme.rail).opacity(0.28),
                    .clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            // Soft track lines — atmosphere, not chrome noise.
            VStack(spacing: 28) {
                ForEach(0..<8, id: \.self) { _ in
                    Rectangle()
                        .fill(TrainTheme.cabinInk.opacity(0.03))
                        .frame(height: 1)
                }
            }
            .offset(y: 40)
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
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .foregroundStyle(kind.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(kind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: TrainTheme.Radius.badge))
    }
}

// MARK: - Buttons

struct DepartButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                    .fill(enabled ? TrainTheme.rail : TrainTheme.muted.opacity(0.35))
            )
            .scaleEffect(configuration.isPressed && enabled ? 0.96 : 1)
            .animation(TrainTheme.Motion.spring, value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.7)
    }
}

struct FocusPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(TrainTheme.cabin)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                    .fill(TrainTheme.signalGreen)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1.2)
                    .background(
                        RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                            .fill(TrainTheme.cabinLift.opacity(0.65))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(TrainTheme.Motion.spring, value: configuration.isPressed)
    }
}

struct TrainFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(
                    Circle()
                        .fill(TrainTheme.rail)
                        .shadow(color: TrainTheme.rail.opacity(0.35), radius: 10, y: 4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切符を追加")
    }
}

// MARK: - Ticket surface

struct TicketSurface: ViewModifier {
    var emphasized: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, TrainTheme.Space.md)
            .padding(.vertical, TrainTheme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: TrainTheme.Radius.ticket)
                    .fill(Color.white.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: TrainTheme.Radius.ticket)
                            .strokeBorder(
                                emphasized ? TrainTheme.rail.opacity(0.45) : TrainTheme.track.opacity(0.7),
                                lineWidth: emphasized ? 1.5 : 1
                            )
                    }
            )
    }
}

extension View {
    func ticketSurface(emphasized: Bool = false) -> some View {
        modifier(TicketSurface(emphasized: emphasized))
    }
}
