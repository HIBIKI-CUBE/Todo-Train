import Observation
import SwiftUI
import TodoTrainSync

@Observable
@MainActor
final class CompanionRideOverlayModel {
    var presentation = RideOverlayPresentation.hidden
    var isTucked = false
    var hovering = false
    var edge = OverlayEdge.trailing
}

struct CompanionRideOverlayView: View {
    @Bindable var model: CompanionRideOverlayModel
    var onPause: () -> Void
    var onResume: () -> Void
    var onStill: () -> Void
    var onRestore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: RideOverlayPresentation { model.presentation }

    var body: some View {
        Group {
            if model.isTucked {
                peek
            } else {
                card
            }
        }
        .frame(
            width: CGFloat(RideOverlayGeometry.cardSize.width),
            height: CGFloat(RideOverlayGeometry.cardSize.height)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(accessibilityRemaining)
        .accessibilityAction(named: "戻す") {
            if model.isTucked { onRestore() }
        }
        .accessibilityAction(named: presentation.canResume ? "再乗車" : "停車") {
            primaryAction()
        }
        .accessibilityAction(named: CabinCopy.still) {
            if presentation.cabinPrompt != nil { onStill() }
        }
    }

    private var card: some View {
        HStack(spacing: 0) {
            handle
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                if let line = presentation.failureLine {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(RideOverlayPalette.overtime)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                } else if let prompt = presentation.cabinPrompt {
                    Text(prompt)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                } else if let occupancy = presentation.occupancy {
                    occupancyStrip(occupancy)
                } else if let line = presentation.nextBlockLine {
                    Text(line)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                } else if let status = presentation.statusLine {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }

                Spacer(minLength: 0)
                bottomRow
            }
        }
        .background(Color.black)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CGFloat(RideOverlayGeometry.cornerRadius), style: .continuous)
    }

    private var handle: some View {
        Capsule()
            .fill(.white.opacity(0.4))
            .frame(width: 4, height: 28)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func occupancyStrip(_ occupancy: RideOccupancyInstrument) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(occupancy.prefix == "次" ? "次" : "いま")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text(occupancy.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            Text(occupancy.clock)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.88))
            if let minutes = occupancy.minutes {
                Text("\(minutes)分")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(occupancy.spokenLine)
    }

    private var bottomRow: some View {
        ZStack {
            progressRow
                .opacity(showsCabinActions || showsAction ? 0 : 1)
            if showsCabinActions {
                cabinActionRow
            } else {
                actionRow
                    .opacity(showsAction ? 1 : 0)
            }
        }
        .frame(height: 40)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: showsAction || showsCabinActions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bottomAccessibilityLabel)
        .accessibilityValue(showsAction || showsCabinActions ? "" : presentation.remainingLabel)
    }

    private var showsCabinActions: Bool {
        presentation.cabinPrompt != nil && !model.isTucked
    }

    private var showsAction: Bool {
        model.hovering
            && !model.isTucked
            && presentation.cabinPrompt == nil
            && (presentation.canPause || presentation.canResume)
    }

    private var progressRow: some View {
        GeometryReader { geo in
            let fillWidth = CGFloat(
                RideOverlayGeometry.fillLength(
                    progress: presentation.progress,
                    total: geo.size.width
                )
            )
            ZStack(alignment: .leading) {
                Color.black
                HStack(spacing: 0) {
                    RideOverlayPalette.fill(for: presentation)
                        .frame(width: fillWidth)
                    Spacer(minLength: 0)
                }
                occupancyProgressMarks(width: geo.size.width, height: geo.size.height)
                remainingDigits(RideOverlayPalette.onTrack)
                remainingDigits(RideOverlayPalette.onFill(for: presentation))
                    .mask {
                        HStack(spacing: 0) {
                            Color.white.frame(width: fillWidth)
                            Color.clear
                        }
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
    }

    @ViewBuilder
    private func occupancyProgressMarks(width: CGFloat, height: CGFloat) -> some View {
        if let occupancy = presentation.occupancy {
            if let start = occupancy.spanStart, let end = occupancy.spanEnd, end > start {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: max(6, width * (end - start)), height: height)
                    .offset(x: width * start)
            }
            if let mark = occupancy.markPosition {
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 5, height: height)
                    .offset(x: width * mark - 2.5)
            }
        }
    }

    private func remainingDigits(_ color: Color) -> some View {
        Text(presentation.remainingLabel)
            .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: presentation.canResume ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(presentation.canResume ? "再乗車" : "停車")
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(actionColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var cabinActionRow: some View {
        HStack(spacing: 0) {
            Text(CabinCopy.still)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1)
                .padding(.vertical, 8)
            HStack(spacing: 6) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("停車")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(presentation.isSending ? .white.opacity(0.35) : RideOverlayPalette.final)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }

    private var bottomAccessibilityLabel: String {
        if showsCabinActions { return "\(CabinCopy.prompt) \(CabinCopy.still) または 停車" }
        if showsAction { return presentation.canResume ? "再乗車" : "停車" }
        return "残り時間"
    }

    private var actionColor: Color {
        if presentation.isSending { return .white.opacity(0.35) }
        return presentation.canResume ? RideOverlayPalette.resume : RideOverlayPalette.final
    }

    private var peek: some View {
        HStack(spacing: 0) {
            if model.edge == .leading {
                Color.clear
            }
            peekTab
            if model.edge == .trailing {
                Color.clear
            }
        }
    }

    private var peekTab: some View {
        ZStack {
            peekProgressBackground
            if model.hovering {
                Color.black
                Image(systemName: model.edge == .leading ? "chevron.right" : "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(presentation.peekTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 0.5)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(model.edge == .leading ? -90 : 90))
            }
        }
        .frame(width: CGFloat(RideOverlayGeometry.peekReveal))
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.hovering)
        .accessibilityHidden(true)
    }

    /// Vertical time bar: elapsed grows from the bottom, remainder stays black (sketch Hidden).
    private var peekProgressBackground: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RideOverlayPalette.fill(for: presentation)
                    .frame(
                        height: CGFloat(
                            RideOverlayGeometry.fillLength(
                                progress: presentation.progress,
                                total: geo.size.height
                            )
                        )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(Color.black)
            .overlay {
                occupancyPeekMarks(height: geo.size.height)
            }
        }
    }

    @ViewBuilder
    private func occupancyPeekMarks(height: CGFloat) -> some View {
        if let occupancy = presentation.occupancy {
            ZStack(alignment: .bottom) {
                if let start = occupancy.spanStart, let end = occupancy.spanEnd, end > start {
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(height: max(4, height * (end - start)))
                        .padding(.bottom, height * start)
                }
                if let mark = occupancy.markPosition {
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(height: 5)
                        .padding(.bottom, max(0, height * mark - 2.5))
                }
            }
        }
    }

    private var accessibilityRemaining: String {
        if model.isTucked { return "画面の外に出しています" }
        if presentation.isPaused { return "停車中 \(presentation.remainingLabel)" }
        if presentation.isOvertime { return "超過 \(presentation.remainingLabel)" }
        return "残り \(presentation.remainingLabel)"
    }

    private func primaryAction() {
        if presentation.isSending { return }
        if presentation.canResume {
            onResume()
        } else if presentation.canPause {
            onPause()
        }
    }
}

enum RideOverlayPalette {
    /// Same RGB as iOS `CockpitColors` (Focus / Live Activity).
    static let cruise = Color.white
    static let approach = Color(red: 1.0, green: 0.82, blue: 0.42)
    static let final = Color(red: 1.0, green: 0.72, blue: 0.28)
    static let overtime = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let resume = Color(red: 0.35, green: 0.78, blue: 0.52)
    static let onTrack = Color.white

    static func fill(for presentation: RideOverlayPresentation) -> Color {
        switch presentation.timerPhase {
        case .cruise: cruise
        case .approach: approach
        case .final: final
        case .overtime: overtime
        }
    }

    static func onFill(for presentation: RideOverlayPresentation) -> Color {
        presentation.timerPhase == .overtime ? .white : .black
    }
}
