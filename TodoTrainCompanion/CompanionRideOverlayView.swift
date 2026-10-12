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
    /// Second step of 延長. Local to the PiP. Nothing is sent until a preset.
    var extendPicker = false
    /// Edge lamp while the card is tucked. The card stays out.
    var edgeLamp = false
}

struct CompanionRideOverlayView: View {
    @Bindable var model: CompanionRideOverlayModel
    var onPause: () -> Void
    var onResume: () -> Void
    var onStill: () -> Void
    var onRestore: () -> Void
    var onNudgeChoice: (NudgeChoice) -> Void
    var onExtendPreset: (Int) -> Void
    var onCancelExtend: () -> Void
    var onBoardReserved: () -> Void
    var onCloseGap: () -> Void
    var onPausePrompt: (PausePromptAnswer) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: RideOverlayPresentation { model.presentation }

    var body: some View {
        pauseAccess(cabinAccess(framed))
    }

    private var framed: some View {
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
        .accessibilityLabel(
            presentation.showsArrivalGap
                ? (presentation.nudgePrompt ?? CabinCopy.idle)
                : presentation.title
        )
        .accessibilityValue(accessibilityRemaining)
    }

    private func cabinAccess<Content: View>(_ content: Content) -> some View {
        content
            .accessibilityAction(named: "出す") {
                if model.isTucked { onRestore() }
            }
            .accessibilityAction(named: presentation.canResume ? "再乗車" : CabinCopy.pause) {
                if showsNudgeActions && !model.extendPicker {
                    onNudgeChoice(.paused)
                } else if !showsNudgeActions {
                    primaryAction()
                }
            }
            .accessibilityAction(named: CabinCopy.still) {
                if presentation.cabinPrompt != nil { onStill() }
                if showsNudgeActions && !model.extendPicker { onNudgeChoice(.stillOnIt) }
            }
            .accessibilityAction(named: CabinCopy.extend) {
                if showsNudgeActions && !model.extendPicker { onNudgeChoice(.willExtend) }
            }
            .accessibilityAction(named: CabinCopy.arrived) {
                if showsNudgeActions && !model.extendPicker { onNudgeChoice(.alreadyDone) }
            }
    }

    private func pauseAccess<Content: View>(_ content: Content) -> some View {
        content
            .accessibilityAction(named: CabinCopy.extendFive) {
                if model.extendPicker { onExtendPreset(300) }
            }
            .accessibilityAction(named: CabinCopy.extendTen) {
                if model.extendPicker { onExtendPreset(600) }
            }
            .accessibilityAction(named: CabinCopy.extendFifteen) {
                if model.extendPicker { onExtendPreset(900) }
            }
            .accessibilityAction(named: CabinCopy.back) {
                if model.extendPicker { onCancelExtend() }
            }
            .accessibilityAction(named: CabinCopy.board) {
                if presentation.showsArrivalGap && presentation.canBoardReserved { onBoardReserved() }
            }
            .accessibilityAction(named: CabinCopy.close) {
                if presentation.showsArrivalGap { onCloseGap() }
            }
            .accessibilityAction(named: PauseInputCopy.resume) {
                if presentation.pausePrompt != nil { onPausePrompt(.resume) }
            }
            .accessibilityAction(named: PauseInputCopy.keepPaused) {
                if presentation.pausePrompt != nil { onPausePrompt(.keepPaused) }
            }
    }

    private var showsNudgeActions: Bool {
        presentation.showsNudgeChoices && !model.isTucked
    }

    private var card: some View {
        HStack(spacing: 0) {
            handle
            VStack(alignment: .leading, spacing: 0) {
            if presentation.showsArrivalGap {
                gapColumn
            } else if presentation.pausePrompt != nil {
                pausePromptColumn
            } else if showsNudgeActions || model.extendPicker {
                nudgeColumn
            } else {
                classicColumn
            }
            }
        }
        .background(Color.black)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var classicColumn: some View {
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
                    .lineLimit(2)
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

    /// Reserved face, or the idle line. No timetable preview.
    private var gapColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(presentation.holdLamp ? RideOverlayPalette.approach : Color.white.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(presentation.nudgePrompt ?? CabinCopy.idle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(height: 36, alignment: .center)

            if presentation.canBoardReserved, !presentation.title.isEmpty {
                Text(presentation.title)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if let line = presentation.failureLine ?? (presentation.isSending ? presentation.statusLine : nil) {
                Text(line)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
            }

            gapChoices
                .frame(height: 40)
        }
    }

    private var gapChoices: some View {
        let titles = presentation.canBoardReserved
            ? [CabinCopy.board, CabinCopy.close]
            : [CabinCopy.close]
        return equalChoiceRow(titles)
            .opacity(presentation.isSending ? 0.35 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(titles.joined(separator: " "))
            .accessibilityHint(
                presentation.canBoardReserved ? CabinCopy.boardHint : CabinCopy.closeGapHint
            )
    }

    /// Same question row as the nudge, then two answers.
    private var pausePromptColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(presentation.holdLamp ? RideOverlayPalette.approach : Color.white.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(presentation.pausePrompt ?? PauseInputCopy.questionBare)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .accessibilityHint(PauseInputCopy.questionHint)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(height: 36, alignment: .center)

            nudgeInstrument
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            equalChoiceRow([PauseInputCopy.resume, PauseInputCopy.keepPaused])
                .frame(height: 40)
                .opacity(presentation.isSending ? 0.35 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(PauseInputCopy.resume) \(PauseInputCopy.keepPaused)")
                .accessibilityHint("\(PauseInputCopy.resumeHint) \(PauseInputCopy.keepPausedHint)")
        }
    }

    /// Question, instruments, then four equal answers.
    private var nudgeColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(presentation.holdLamp ? RideOverlayPalette.approach : Color.white.opacity(0.22))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(presentation.nudgePrompt ?? CabinCopy.question(title: presentation.title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .accessibilityHint(CabinCopy.questionHint)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(height: 28, alignment: .center)

            nudgeInstrument
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let line = presentation.failureLine ?? (presentation.isSending ? presentation.statusLine : nil) {
                Text(line)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            nudgeChoices
                .frame(height: 40)
        }
    }

    private var nudgeInstrument: some View {
        ZStack {
            if let caption = presentation.instrumentCaption {
                Text(caption)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(RideOverlayPalette.fill(for: presentation))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
            } else {
                progressRow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.instrumentCaption ?? "残り \(presentation.remainingLabel)")
    }

    private var nudgeChoices: some View {
        equalChoiceRow(
            model.extendPicker
                ? [CabinCopy.extendFive, CabinCopy.extendTen, CabinCopy.extendFifteen, CabinCopy.back]
                : [CabinCopy.still, CabinCopy.extend, CabinCopy.arrived, CabinCopy.pause]
        )
        .opacity(presentation.isSending ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            model.extendPicker
                ? "\(CabinCopy.extendFive) \(CabinCopy.extendTen) \(CabinCopy.extendFifteen) \(CabinCopy.back)"
                : "\(CabinCopy.still) \(CabinCopy.extend) \(CabinCopy.arrived) \(CabinCopy.pause)"
        )
        .accessibilityHint(model.extendPicker ? CabinCopy.extendPickerHint : CabinCopy.questionHint)
    }

    private func equalChoiceRow(_ titles: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
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
            && presentation.pausePrompt == nil
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
        .overlay(alignment: .top) {
            if model.edgeLamp {
                Circle()
                    .fill(RideOverlayPalette.approach)
                    .frame(width: 8, height: 8)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
        }
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
