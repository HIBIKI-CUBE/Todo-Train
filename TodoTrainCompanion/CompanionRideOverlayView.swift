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
    /// Local band. Nil follows the snap: a question shows the first band.
    var reestimateBand: PipReestimateBand?
    /// Picked on the progress band before the declare band opens.
    var reestimateProgress: Double?
    /// Snap fields for declare captions. Refreshed from the runtime when the snap changes.
    var positionActiveSeconds: TimeInterval = 0
    var positionPlannedBudgetSeconds: Int = 0
    var positionRemainingSeconds: Int = 0
    var positionNowUnix: Int = 0
    /// Question already handled by a commit. Same nudge id does not reopen it.
    var settledNudgeID: UUID?
    /// Mirrors the runtime. Non-nil shows 取り消し on the ride card.
    var reestimateUndoUntil: Int?
    /// Edge lamp while the card is tucked. The card stays out.
    var edgeLamp = false

    func activeReestimateBand(showsNudgeChoices: Bool) -> PipReestimateBand? {
        if reestimateUndoUntil != nil { return nil }
        if let reestimateBand { return reestimateBand }
        if showsNudgeChoices, settledNudgeID == nil { return .answers }
        return nil
    }
}

struct CompanionRideOverlayView: View {
    @Bindable var model: CompanionRideOverlayModel
    var onToggleHold: () -> Void
    var onStill: () -> Void
    var onRestore: () -> Void
    var onNudgeChoice: (NudgeChoice) -> Void
    var onOpenProgress: () -> Void
    var onSelectProgress: (Double) -> Void
    var onCommitReestimate: (MacPipReestimateChoice) -> Void
    var onUndoReestimate: () -> Void
    var onBoardReserved: () -> Void
    var onCloseGap: () -> Void
    var onPausePrompt: (PausePromptAnswer) -> Void
    var onAcknowledgeRadio: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var radioLit = true

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
        .clipped()
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
                if activeBand == .answers {
                    onNudgeChoice(.paused)
                } else if activeBand == nil {
                    primaryAction()
                }
            }
            .accessibilityAction(named: CabinCopy.still) {
                if presentation.cabinPrompt != nil { onStill() }
                if activeBand == .answers { onNudgeChoice(.stillOnIt) }
            }
            .accessibilityAction(named: PipBandCopy.positionCheck) {
                if activeBand == .answers { onOpenProgress() }
            }
            .accessibilityAction(named: CabinCopy.arrived) {
                if activeBand == .answers { onNudgeChoice(.alreadyDone) }
            }
            .accessibilityAction(named: PipBandCopy.share30) {
                if activeBand == .progress { onSelectProgress(0.3) }
            }
            .accessibilityAction(named: PipBandCopy.share50) {
                if activeBand == .progress { onSelectProgress(0.5) }
            }
            .accessibilityAction(named: PipBandCopy.share80) {
                if activeBand == .progress { onSelectProgress(0.8) }
            }
            .accessibilityAction(named: PipBandCopy.recovery) {
                if activeBand == .declare { commitDeclare(.recovery) }
            }
            .accessibilityAction(named: PipBandCopy.adjust) {
                if activeBand == .declare { commitDeclare(.adjust) }
            }
            .accessibilityAction(named: PipBandCopy.undo) {
                if model.reestimateUndoUntil != nil { onUndoReestimate() }
            }
    }

    private func pauseAccess<Content: View>(_ content: Content) -> some View {
        content
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

    private var activeBand: PipReestimateBand? {
        guard !model.isTucked else { return nil }
        return model.activeReestimateBand(showsNudgeChoices: presentation.showsNudgeChoices)
    }

    private var card: some View {
        HStack(spacing: 0) {
            handle
            VStack(alignment: .leading, spacing: 0) {
            if presentation.showsArrivalGap {
                gapColumn
            } else if presentation.pausePrompt != nil {
                pausePromptColumn
            } else if let band = activeBand {
                reestimateColumn(band)
            } else {
                classicColumn
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            radioLamp
                .padding(.top, 6)
                .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var radioLamp: some View {
        let radio = presentation.radio
        if radio.phase != .quiet {
            let blinks = radio.blinks && !reduceMotion && !radio.dimmed
            let face = radioFace(radio, blinks: blinks)
            if radio.phase == .recovered {
                face.accessibilityHidden(true)
            } else {
                Button(action: onAcknowledgeRadio) {
                    face
                }
                .buttonStyle(.plain)
                .accessibilityLabel(radio.phase == .outOfContact ? SyncCopy.radioOut : "再接続中")
                .accessibilityValue(radio.lastReceivedClock ?? "")
                .accessibilityHint("確認すると点滅が止まります")
            }
        }
    }

    private func radioFace(_ radio: RelayRadioReading, blinks: Bool) -> some View {
        let color = radioColor(radio.phase, dimmed: radio.dimmed)
        return VStack(spacing: 1) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
                    .opacity(blinks && !radioLit ? 0.25 : 1)
                if radio.phase == .outOfContact, let clock = radio.lastReceivedClock {
                    Text(clock)
                        .font(.system(size: 7, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(radio.dimmed ? 0.7 : 1))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            if radio.phase == .outOfContact, let clock = radio.lastReceivedClock {
                Text(clock)
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .onAppear { pulseRadio(blinks) }
        .onChange(of: blinks) { _, blinking in
            pulseRadio(blinking)
        }
    }

    private func pulseRadio(_ blinks: Bool) {
        guard blinks else {
            radioLit = true
            return
        }
        radioLit = true
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            radioLit = false
        }
    }

    private func radioColor(_ phase: RelayRadioPhase, dimmed: Bool) -> Color {
        let base: Color
        switch phase {
        case .quiet:
            base = .clear
        case .reconnecting:
            base = RideOverlayPalette.approach
        case .outOfContact:
            base = Color(red: 0.86, green: 0.16, blue: 0.18)
        case .recovered:
            base = RideOverlayPalette.resume
        }
        return dimmed ? base.opacity(0.4) : base
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
                .frame(maxWidth: .infinity, alignment: .leading)

            if let line = presentation.failureLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(RideOverlayPalette.overtime)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let prompt = presentation.cabinPrompt {
                Text(prompt)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                scheduleSlot
            }

            Spacer(minLength: 0)
            bottomRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One line, always the same height, so a schedule appearing does not move the title or the bar.
    private var scheduleSlot: some View {
        scheduleReadout
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 24, alignment: .leading)
            .clipped()
    }

    @ViewBuilder
    private var scheduleReadout: some View {
        if let occupancy = presentation.occupancy {
            occupancyStrip(occupancy)
        } else if let line = presentation.nextBlockLine {
            Text(line)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if let status = presentation.statusLine {
            Text(status)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Color.clear
                .accessibilityHidden(true)
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

    /// Heading, instruments, then one quartered band. Nothing in the band starts selected.
    private func reestimateColumn(_ band: PipReestimateBand) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(bandHeading(band))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
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

            bandChoices(band)
                .frame(height: 40)
        }
    }

    private func bandHeading(_ band: PipReestimateBand) -> String {
        switch band {
        case .answers:
            presentation.nudgePrompt ?? CabinCopy.question(title: presentation.title)
        case .progress, .declare:
            PipBandCopy.positionHeading
        }
    }

    private func bandTitles(_ band: PipReestimateBand) -> [String] {
        switch band {
        case .answers:
            return [CabinCopy.still, PipBandCopy.positionCheck, CabinCopy.arrived, CabinCopy.pause]
        case .progress:
            return [PipBandCopy.share30, PipBandCopy.share50, PipBandCopy.share80]
        case .declare:
            guard let labels = declareLabels else {
                return [PipBandCopy.adjust]
            }
            if labels.showsRecovery {
                return [PipBandCopy.recovery, PipBandCopy.adjust]
            }
            return [PipBandCopy.adjust]
        }
    }

    private func bandHint(_ band: PipReestimateBand) -> String {
        switch band {
        case .answers:
            CabinCopy.questionHint
        case .progress:
            PipBandCopy.shareHint
        case .declare:
            PipBandCopy.declareHint
        }
    }

    private var declareLabels: PipPositionDeclareLabels? {
        guard let progress = model.reestimateProgress else { return nil }
        let now = Date(timeIntervalSince1970: TimeInterval(model.positionNowUnix))
        return MacPipReestimate.declareLabels(
            progress: progress,
            activeSeconds: model.positionActiveSeconds,
            plannedBudgetSeconds: model.positionPlannedBudgetSeconds,
            remainingSeconds: model.positionRemainingSeconds,
            now: now
        )
    }

    private func commitDeclare(_ declaration: PipReestimateDeclaration) {
        guard let progress = model.reestimateProgress else { return }
        switch declaration {
        case .recovery:
            onCommitReestimate(
                .recovery(
                    progress: progress,
                    committedRemainingSeconds: model.positionRemainingSeconds
                )
            )
        case .adjust:
            onCommitReestimate(.adjust(progress: progress))
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

    private func bandChoices(_ band: PipReestimateBand) -> some View {
        Group {
            if band == .declare, let labels = declareLabels {
                declareChoiceRow(labels)
            } else {
                equalChoiceRow(bandTitles(band))
            }
        }
        .opacity(presentation.isSending ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bandTitles(band).joined(separator: " "))
        .accessibilityHint(bandHint(band))
    }

    private func declareChoiceRow(_ labels: PipPositionDeclareLabels) -> some View {
        HStack(spacing: 0) {
            if labels.showsRecovery, let recoveryCaption = labels.recoveryCaption {
                declareCell(title: PipBandCopy.recovery, caption: recoveryCaption)
                divider
                declareCell(title: PipBandCopy.adjust, caption: labels.adjustCaption)
            } else {
                declareCell(title: PipBandCopy.adjust, caption: labels.adjustCaption)
            }
        }
        .background(Color.black)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    private func declareCell(title: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(occupancy.prefix == "次" ? "次" : "いま")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 28, alignment: .leading)
            Text(occupancy.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(occupancy.clock)
                if let minutes = occupancy.minutes {
                    Text("\(minutes)分")
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(occupancy.spokenLine)
    }

    private var bottomRow: some View {
        ZStack {
            if model.reestimateUndoUntil != nil {
                undoRow
            } else {
                progressRow
                    .opacity(showsCabinActions || showsAction ? 0 : 1)
                if showsCabinActions {
                    cabinActionRow
                } else {
                    actionRow
                        .opacity(showsAction ? 1 : 0)
                }
            }
        }
        .frame(height: 40)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: showsAction || showsCabinActions || model.reestimateUndoUntil != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bottomAccessibilityLabel)
        .accessibilityValue(showsAction || showsCabinActions || model.reestimateUndoUntil != nil ? "" : presentation.remainingLabel)
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
            if let start = occupancy.spanStart, let end = occupancy.spanEnd, end > start,
               let span = RideOverlayGeometry.containedSpan(start: start, end: end, length: width) {
                let bandHeight = min(CGFloat(4), height)
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: span.length, height: bandHeight)
                    .frame(height: height, alignment: .top)
                    .offset(x: span.origin)
            }
            if let mark = occupancy.markPosition,
               let tick = RideOverlayGeometry.containedTick(position: mark, length: width, thickness: 2) {
                Rectangle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: tick.length, height: height)
                    .offset(x: tick.origin)
            }
        }
    }

    private func remainingDigits(_ color: Color) -> some View {
        Text(presentation.remainingLabel)
            .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var undoRow: some View {
        Text(PipBandCopy.undo)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
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
        if model.reestimateUndoUntil != nil { return PipBandCopy.undo }
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
            if presentation.radio.phase != .quiet {
                radioLamp
                    .scaleEffect(0.72)
                    .padding(.top, 4)
            } else if model.edgeLamp {
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
                if let start = occupancy.spanStart, let end = occupancy.spanEnd, end > start,
                   let span = RideOverlayGeometry.containedSpan(start: start, end: end, length: height) {
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(height: span.length)
                        .padding(.bottom, span.origin)
                }
                if let mark = occupancy.markPosition,
                   let tick = RideOverlayGeometry.containedTick(position: mark, length: height, thickness: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(0.92))
                        .frame(height: tick.length)
                        .padding(.bottom, tick.origin)
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
        onToggleHold()
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

#if DEBUG
@MainActor
func ridePreview(_ presentation: RideOverlayPresentation) -> some View {
    let model = CompanionRideOverlayModel()
    model.presentation = presentation
    return CompanionRideOverlayView(
        model: model,
        onToggleHold: {},
        onStill: {},
        onRestore: {},
        onNudgeChoice: { _ in },
        onOpenProgress: {},
        onSelectProgress: { _ in },
        onCommitReestimate: { _ in },
        onUndoReestimate: {},
        onBoardReserved: {},
        onCloseGap: {},
        onPausePrompt: { _ in },
        onAcknowledgeRadio: {}
    )
}

@MainActor
func rideReestimatePreview(
    _ band: PipReestimateBand,
    title: String = "原稿",
    progress: Double? = nil
) -> some View {
    let model = CompanionRideOverlayModel()
    model.presentation = rideSnap(title: title)
    model.reestimateBand = band
    model.positionActiveSeconds = 21 * 60
    model.positionPlannedBudgetSeconds = 30 * 60
    model.positionRemainingSeconds = 9 * 60
    model.positionNowUnix = 1_768_000_120
    if let progress {
        model.reestimateProgress = progress
    }
    return CompanionRideOverlayView(
        model: model,
        onToggleHold: {},
        onStill: {},
        onRestore: {},
        onNudgeChoice: { _ in },
        onOpenProgress: {},
        onSelectProgress: { _ in },
        onCommitReestimate: { _ in },
        onUndoReestimate: {},
        onBoardReserved: {},
        onCloseGap: {},
        onPausePrompt: { _ in },
        onAcknowledgeRadio: {}
    )
}

func rideSnap(
    title: String,
    nextTitle: String? = nil,
    startsAt: Int? = nil,
    endsAt: Int? = nil
) -> RideOverlayPresentation {
    let snap = SnapPlaintext(
        rev: 1,
        sessionId: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
        ticketId: UUID(uuidString: "00000000-0000-0000-0000-000000000002"),
        title: title,
        phase: .running,
        startedAt: 1_768_000_000,
        estimatedSeconds: 1_500,
        pausedAccumulated: 0,
        pausedAt: nil,
        boardedDeviceID: nil,
        serviceActive: true,
        cabinEnabled: false,
        nextBlockTitle: nextTitle,
        nextBlockStartsAt: startsAt,
        nextBlockEndsAt: endsAt
    )
    return RideOverlayPresentation.make(
        MenuBarInput(
            pairing: .paired,
            snap: snap,
            now: 1_768_000_120,
            cabinEnabledLocal: false
        )
    )
}

@MainActor
func ridePreviewCanvas(_ presentation: RideOverlayPresentation) -> some View {
    ridePreview(presentation)
        .padding(24)
        .background(Color(white: 0.32))
}

#Preview("予定なし") {
    ridePreviewCanvas(rideSnap(title: "週次レポート"))
}

#Preview("短い予定") {
    ridePreviewCanvas(
        rideSnap(title: "週次レポート", nextTitle: "定例", startsAt: 1_768_000_400)
    )
}

#Preview("長い予定") {
    ridePreviewCanvas(
        rideSnap(
            title: "週次レポートの準備を終えてからレビューに入る",
            nextTitle: "四半期の振り返りと次のスプリントの計画を書く",
            startsAt: 1_768_003_780
        )
    )
}

#Preview("位置確認 一段") {
    rideReestimatePreview(.answers)
        .padding(24)
        .background(Color(white: 0.32))
}

#Preview("位置確認 二段") {
    rideReestimatePreview(.progress)
        .padding(24)
        .background(Color(white: 0.32))
}

#Preview("位置確認 三段") {
    rideReestimatePreview(.declare, progress: 0.5)
        .padding(24)
        .background(Color(white: 0.32))
}

#Preview("いまの占有") {
    ridePreviewCanvas(
        rideSnap(
            title: "原稿",
            nextTitle: "デザインレビュー",
            startsAt: 1_768_000_000,
            endsAt: 1_768_001_320
        )
    )
}
#endif
