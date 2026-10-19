//
//  FocusReestimatePanel.swift
//  Todo train
//

import SwiftUI
import TodoTrainSync
import TodoTrainTicketUI

/// 指を離したあとの段。記録はしない。
enum PositionCheckFlow {
    enum Release: Equatable {
        case check
        case declare
        case full
    }

    static func stageAfterRelease(
        percent: Int,
        activeSeconds: TimeInterval,
        judgment: PunctualityJudgment.Judgment
    ) -> Release {
        if percent >= 100 { return .full }
        guard percent > 0 else { return .check }
        let progress = Double(percent) / 100
        guard let projected = PositionReport.projection(activeSeconds: activeSeconds, progress: progress) else {
            return .check
        }
        if PositionReport.isOnTime(projectedTotal: projected, judgment: judgment) {
            return .check
        }
        return .declare
    }
}

struct FocusReestimatePanel: View {
    let activeSeconds: TimeInterval
    let remainingSeconds: TimeInterval
    let plannedBudgetSeconds: Int
    let judgment: PunctualityJudgment.Judgment
    let recoverySealLuxury: Double?
    let now: Date
    let onCommit: (ReestimateDeclaration, Double, Int) -> Void
    let onArrive: () -> Void
    let onClose: () -> Void
    let onLiveChange: (Int, Bool) -> Void

    @State private var stage: Stage
    @State private var progressPercent: Int
    @State private var isTouching: Bool
    @State private var inputsLocked = false
    @State private var declareGeneration = 0
    @State private var homeBoundaryPulse = 0

    private enum Stage {
        case check
        case declare
        case full
    }

    private let stopPercents = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

    init(
        activeSeconds: TimeInterval,
        remainingSeconds: TimeInterval,
        plannedBudgetSeconds: Int,
        judgment: PunctualityJudgment.Judgment,
        recoverySealLuxury: Double?,
        now: Date,
        onCommit: @escaping (ReestimateDeclaration, Double, Int) -> Void,
        onArrive: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onLiveChange: @escaping (Int, Bool) -> Void = { _, _ in },
        previewConfiguration: FocusReestimatePreviewConfiguration? = nil
    ) {
        self.activeSeconds = activeSeconds
        self.remainingSeconds = remainingSeconds
        self.plannedBudgetSeconds = plannedBudgetSeconds
        self.judgment = judgment
        self.recoverySealLuxury = recoverySealLuxury
        self.now = now
        self.onCommit = onCommit
        self.onArrive = onArrive
        self.onClose = onClose
        self.onLiveChange = onLiveChange

        if let previewConfiguration {
            switch previewConfiguration.stage {
            case .check:
                _stage = State(initialValue: .check)
            case .declare:
                _stage = State(initialValue: .declare)
            case .full:
                _stage = State(initialValue: .full)
            }
            _progressPercent = State(initialValue: previewConfiguration.progressValue)
            _isTouching = State(initialValue: previewConfiguration.isTouching)
        } else {
            _stage = State(initialValue: .check)
            _progressPercent = State(initialValue: 0)
            _isTouching = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            FocusControlDivider()
            stageBody
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .opacity(inputsLocked ? 0.55 : 1)
                .allowsHitTesting(!inputsLocked)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FocusPanel.fill)
        .onAppear { reportLive() }
        .onDisappear { onLiveChange(0, false) }
        .onChange(of: progressPercent) { previous, next in
            if previous > 0, previous < 100, next > 0, next < 100,
               insideHome(previous) != insideHome(next) {
                homeBoundaryPulse += 1
            }
            reportLive()
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: homeBoundaryPulse)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("位置確認")
                .font(.system(size: 16, weight: .bold))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button("閉じる", action: onClose)
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(FocusPanel.ink)
        .background(FocusPanel.fill)
    }

    private var stageBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            readout
                .accessibilityHidden(true)
            gauge
            if stage == .declare {
                choices
            }
            if stage == .full {
                fullArrival
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        if progressPercent <= 0 {
            if let tenth = PositionReport.scheduledTenth(
                activeSeconds: activeSeconds,
                plannedSeconds: plannedBudgetSeconds
            ) {
                Text(PositionReportWording.scheduledLine(tenth: tenth))
                    .font(.body.weight(.medium))
                    .foregroundStyle(FocusPanel.ink)
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                Text(PositionReportWording.shareLine(tenth: shareTenth))
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(FocusPanel.ink)
                if progressPercent < 100 {
                    PunctualityHomeSignalLamp(state: insideHome(progressPercent) ? .green : .yellow)
                }
                if let projectionPhrase {
                    Text(projectionPhrase)
                        .font(.body.weight(.medium))
                        .foregroundStyle(FocusPanel.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var gauge: some View {
        EstimateSnapGauge(
            minutes: $progressPercent,
            highlightedMinutes: scheduledHighlightMinutes,
            stopMinutes: stopPercents,
            maxMinutes: 100,
            startsAtLeftUnselected: true,
            bandRangeMinutes: homeBandMinutes,
            requiresDragToCommit: false,
            accessibilityLabelText: "位置確認",
            style: .cabin,
            homeBandLit: answerIsInsideHome,
            accessibilityValueText: gaugeAccessibilityValue,
            onCommit: { handleReleased() },
            onTouchingChange: { touching in
                isTouching = touching
                if touching {
                    declareGeneration += 1
                    inputsLocked = false
                    if stage != .check {
                        stage = .check
                    }
                }
                reportLive(touching: touching)
            }
        )
    }

    @ViewBuilder
    private var choices: some View {
        if let progress = selectedProgress,
           let projectedArrival = PositionReport.projectedArrival(
               now: now,
               activeSeconds: activeSeconds,
               progress: progress
           ) {
            if showsRecoveryOption {
                HStack(spacing: 10) {
                    declarationCell(
                        title: "回復運転",
                        caption: PositionReportWording.recoveryCaption(arrival: originalScheduledArrival),
                        sealLuxury: recoverySealLuxury,
                        action: { commit(.recovery) }
                    )
                    declarationCell(
                        title: "運転調整",
                        caption: PositionReportWording.adjustCaption(arrival: projectedArrival),
                        sealLuxury: PositionReport.adjustLuxuryPreview(progress: progress),
                        action: { commit(.adjust) }
                    )
                }
            } else {
                declarationCell(
                    title: "運転調整",
                    caption: PositionReportWording.adjustCaption(arrival: projectedArrival),
                    sealLuxury: PositionReport.adjustLuxuryPreview(progress: progress),
                    action: { commit(.adjust) }
                )
            }
        }
    }

    private var showsRecoveryOption: Bool {
        PositionReport.showsRecoveryDeclaration(
            activeSeconds: activeSeconds,
            plannedBudgetSeconds: plannedBudgetSeconds
        )
    }

    private func declarationCell(
        title: String,
        caption: String,
        sealLuxury: Double?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FocusPanel.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if let sealLuxury {
                    PunctualitySealSample(luxury: sealLuxury)
                }
            }
            .foregroundStyle(FocusPanel.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FocusPanel.fillRaised)
        }
        .buttonStyle(.plain)
    }

    private var fullArrival: some View {
        FocusControlButton(
            title: "到着",
            systemImage: "flag.checkered",
            fill: TrainTheme.signalGreen,
            foreground: .black,
            prominence: .primary,
            action: onArrive
        )
        .frame(height: 52)
    }

    private var shareTenth: Int {
        progressPercent >= 100 ? 10 : progressPercent / 10
    }

    private var selectedProgress: Double? {
        guard progressPercent > 0, progressPercent < 100 else { return nil }
        return Double(progressPercent) / 100
    }

    private var answerIsInsideHome: Bool {
        insideHome(progressPercent)
    }

    private var projectionPhrase: String? {
        if progressPercent >= 100 { return PositionReportWording.arrivalPointLine }
        guard progressPercent > 0 else { return nil }
        if answerIsInsideHome { return PositionReportWording.onTimeLine }
        guard let progress = selectedProgress,
              let arrival = PositionReport.projectedArrival(
                  now: now,
                  activeSeconds: activeSeconds,
                  progress: progress
              )
        else { return nil }
        return PositionReportWording.projectionLine(arrival: arrival)
    }

    private var gaugeAccessibilityValue: String {
        guard progressPercent > 0 else { return PositionReportWording.unselectedValue }
        if let projectionPhrase {
            return PositionReportWording.gaugeValue(tenth: shareTenth, phrase: projectionPhrase)
        }
        return PositionReportWording.shareLine(tenth: shareTenth)
    }

    private var scheduledHighlightMinutes: Int? {
        guard let tenth = PositionReport.scheduledTenth(
            activeSeconds: activeSeconds,
            plannedSeconds: plannedBudgetSeconds
        ) else { return nil }
        return tenth * 10
    }

    private var homeBandMinutes: ClosedRange<Int>? {
        guard let range = PositionReport.onTimeProgressRange(
            activeSeconds: activeSeconds,
            lower: judgment.lowerBound,
            upper: judgment.upperBound
        ) else { return nil }
        let low = Int((range.lowerBound * 100).rounded())
        let high = Int((range.upperBound * 100).rounded())
        guard high > low else { return nil }
        return low...high
    }

    /// いまの予定着（回復運転の副題）。超過中は過去の元着時刻のまま。
    private var originalScheduledArrival: Date {
        now.addingTimeInterval(remainingSeconds)
    }

    private func insideHome(_ percent: Int) -> Bool {
        guard percent > 0, percent < 100 else { return false }
        let progress = Double(percent) / 100
        guard let projected = PositionReport.projection(activeSeconds: activeSeconds, progress: progress) else {
            return false
        }
        return PositionReport.isOnTime(projectedTotal: projected, judgment: judgment)
    }

    private func handleReleased() {
        let next = PositionCheckFlow.stageAfterRelease(
            percent: progressPercent,
            activeSeconds: activeSeconds,
            judgment: judgment
        )
        switch next {
        case .check:
            declareGeneration += 1
            inputsLocked = false
            stage = .check
        case .full:
            declareGeneration += 1
            inputsLocked = false
            withAnimation(TrainTheme.Motion.soft) { stage = .full }
        case .declare:
            scheduleDeclare()
        }
    }

    private func scheduleDeclare() {
        declareGeneration += 1
        let generation = declareGeneration
        inputsLocked = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard generation == declareGeneration else { return }
            withAnimation(TrainTheme.Motion.soft) { stage = .declare }
            inputsLocked = false
        }
    }

    private func commit(_ declaration: ReestimateDeclaration) {
        guard let progress = selectedProgress,
              let projectedInt = PositionReport.projectedTotalSecondsInt(
                  activeSeconds: activeSeconds,
                  progress: progress
              )
        else { return }
        onCommit(declaration, progress, projectedInt)
    }

    private func reportLive(touching: Bool? = nil) {
        onLiveChange(progressPercent, touching ?? isTouching)
    }
}
