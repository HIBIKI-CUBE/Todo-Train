//
//  FocusReestimatePanel.swift
//  Todo train
//

import SwiftUI
import TodoTrainSync
import TodoTrainTicketUI

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

    @State private var stage: Stage
    @State private var progressPercent: Int
    @State private var committedProgress: Double?
    @State private var projectedTotalSeconds: TimeInterval?
    @State private var inputsLocked = false

    private enum Stage {
        case position
        case declare
        case onTimeOnly
        case full
    }

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

        if let previewConfiguration {
            switch previewConfiguration.stage {
            case .position:
                _stage = State(initialValue: .position)
            case .declare:
                _stage = State(initialValue: .declare)
            case .onTimeOnly:
                _stage = State(initialValue: .onTimeOnly)
            case .full:
                _stage = State(initialValue: .full)
            }
            _progressPercent = State(initialValue: previewConfiguration.progressValue)
            _committedProgress = State(initialValue: previewConfiguration.committedProgress)
            _projectedTotalSeconds = State(initialValue: previewConfiguration.projectedTotalSeconds)
        } else {
            _stage = State(initialValue: .position)
            _progressPercent = State(initialValue: 0)
            _committedProgress = State(initialValue: nil)
            _projectedTotalSeconds = State(initialValue: nil)
        }
    }

    private var progressAnswer: Double? {
        guard let committedProgress else { return nil }
        return committedProgress
    }

    private var progressTenth: Int {
        guard progressPercent > 0, progressPercent < 100 else { return 0 }
        return progressPercent / 10
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusPanel.fill)
        .onAppear { lockInputsBriefly() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(headerTitle)
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

    private var headerTitle: String {
        switch stage {
        case .position:
            return "いま何割の地点？"
        case .declare, .onTimeOnly:
            return "指令の見込み"
        case .full:
            return "10割の地点"
        }
    }

    @ViewBuilder
    private var stageBody: some View {
        switch stage {
        case .position:
            positionStage
        case .declare:
            declareStage(showChoices: true)
        case .onTimeOnly:
            declareStage(showChoices: false)
        case .full:
            fullStage
        }
    }

    private var positionStage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if progressPercent == 100 {
                Text("10割")
                    .font(.system(size: 40, weight: .semibold, design: .default))
                    .monospacedDigit()
            } else if progressPercent > 0 {
                Text("\(progressTenth)割")
                    .font(.system(size: 40, weight: .semibold, design: .default))
                    .monospacedDigit()
            } else {
                Text("なぞって答える")
                    .font(.subheadline)
                    .foregroundStyle(FocusPanel.muted)
            }
            FocusPositionBar(progressPercent: $progressPercent) {
                handlePositionCommitted()
            }
        }
    }

    @ViewBuilder
    private func declareStage(showChoices: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let progressAnswer {
                let tenth = Int((progressAnswer * 10).rounded())
                Text(PositionReportWording.progressHeadline(tenth: tenth))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FocusPanel.muted)
            }

            if showChoices, let progressAnswer,
               let projectedArrival = PositionReport.projectedArrival(
                   now: now,
                   activeSeconds: activeSeconds,
                   progress: progressAnswer
               ) {
                let activeMinutes = max(1, Int((activeSeconds / 60).rounded()))
                let tenth = Int((progressAnswer * 10).rounded())
                Text(PositionReportWording.projectionDetail(
                    activeMinutes: activeMinutes,
                    tenth: tenth,
                    projectedArrival: projectedArrival
                ))
                .font(.body.weight(.medium))
                .foregroundStyle(FocusPanel.ink)
                .accessibilityHint("走行時間と答えた割合から出した見込みです。")

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
                            sealLuxury: PositionReport.adjustLuxuryPreview(progress: progressAnswer),
                            action: { commit(.adjust) }
                        )
                    }
                } else {
                    declarationCell(
                        title: "運転調整",
                        caption: PositionReportWording.adjustCaption(arrival: projectedArrival),
                        sealLuxury: PositionReport.adjustLuxuryPreview(progress: progressAnswer),
                        action: { commit(.adjust) }
                    )
                }
            } else {
                Text(PositionReportWording.onTimeProjectionSummary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(FocusPanel.ink)
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

    private var fullStage: some View {
        VStack(spacing: 12) {
            Text("到着の操作を選ぶ")
                .font(.subheadline)
                .foregroundStyle(FocusPanel.muted)
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
    }

    /// いまの予定着（回復運転の副題）。超過中は過去の元着時刻のまま。
    private var originalScheduledArrival: Date {
        now.addingTimeInterval(remainingSeconds)
    }

    private func handlePositionCommitted() {
        guard progressPercent > 0 else { return }
        if progressPercent >= 100 {
            committedProgress = 1.0
            withAnimation(TrainTheme.Motion.soft) { stage = .full }
            return
        }
        let progress = Double(progressPercent) / 100.0
        committedProgress = progress
        guard let projected = PositionReport.projection(activeSeconds: activeSeconds, progress: progress) else {
            return
        }
        projectedTotalSeconds = projected
        if projectedIsOnTime(projected) {
            withAnimation(TrainTheme.Motion.soft) { stage = .onTimeOnly }
        } else {
            withAnimation(TrainTheme.Motion.soft) { stage = .declare }
        }
        lockInputsBriefly()
    }

    private func projectedIsOnTime(_ projectedTotal: TimeInterval) -> Bool {
        projectedTotal >= judgment.lowerBound
            && projectedTotal <= judgment.upperBound + PunctualityJudgment.lateGraceSeconds
    }

    private func commit(_ declaration: ReestimateDeclaration) {
        guard let progressAnswer,
              let projectedInt = PositionReport.projectedTotalSecondsInt(
                  activeSeconds: activeSeconds,
                  progress: progressAnswer
              )
        else { return }
        onCommit(declaration, progressAnswer, projectedInt)
    }

    private func lockInputsBriefly() {
        inputsLocked = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            inputsLocked = false
        }
    }
}
