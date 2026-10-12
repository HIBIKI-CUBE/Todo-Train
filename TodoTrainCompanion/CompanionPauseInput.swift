import AppKit
import Foundation
import TodoTrainSync

/// Sleep, the lock screen, and a dropped relay are not samples.
/// Frontmost-app monitoring and Screen Time are not used.
enum PauseInputCounting {
    static func allows(
        connected: Bool,
        screenLocked: Bool,
        systemAsleep: Bool,
        screensAsleep: Bool
    ) -> Bool {
        connected && !screenLocked && !systemAsleep && !screensAsleep
    }
}

extension CompanionMacRuntime {
    func notePauseInputClock() {
        let observation = PauseInputObservation(
            uptime: ProcessInfo.processInfo.systemUptime,
            unixNow: now,
            secondsSinceLastInput: MacInputIdle.secondsSinceLastInput(),
            counting: PauseInputCounting.allows(
                connected: connection == .connected,
                screenLocked: screenLocked,
                systemAsleep: presence.systemAsleep,
                screensAsleep: presence.screensAsleep
            ),
            phase: snap?.phase ?? .idle,
            sessionId: snap?.sessionId,
            pauseId: snap?.pauseId,
            pausedAt: snap?.pausedAt,
            heldBy: snap?.pauseHeldBy,
            title: snap?.title,
            storedSampled: snap?.macSampledSeconds,
            storedActive: snap?.macActiveSeconds
        )
        let step = pauseInput.step(observation)
        pausePromptLine = step.prompt
        if step.chime, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSSound(named: "Tink")?.play()
        }
        for report in step.reports {
            enqueuePauseInputReport(report)
        }
    }

    func answerPausePrompt(_ choice: PausePromptAnswer) {
        guard let report = pauseInput.answer(choice) else { return }
        pausePromptLine = pauseInput.promptLine
        enqueuePauseInputReport(report)
        if choice == .resume {
            Task { await sendResume() }
        }
    }

    func enqueuePauseInputReport(_ report: PauseInputReport) {
        pendingPauseReports[report.pauseId] = report
        flushPauseInputReports()
    }

    func flushPauseInputReports() {
        let introduced = WireOp.pauseInputReport.introducedIn ?? 12
        guard (peerContract?.contract ?? ContractVersion.legacy) >= introduced else { return }
        let batch = pendingPauseReports
        pendingPauseReports.removeAll()
        guard !batch.isEmpty else { return }
        Task { [weak self] in
            for report in batch.values {
                await self?.sendPauseInputReport(report)
            }
        }
    }

    func sendPauseInputReport(_ report: PauseInputReport) async {
        guard isPaired else {
            keepPauseInputReportIfAbsent(report)
            return
        }
        do {
            let command = CommandPlaintext(
                id: UUID(),
                op: .pauseInputReport,
                sessionId: report.sessionId,
                at: now,
                build: LocalWireBuild.current,
                contract: ContractVersion.contract,
                minReadable: ContractVersion.minReadable,
                pauseId: report.pauseId,
                macSampledSeconds: report.macSampledSeconds,
                macActiveSeconds: report.macActiveSeconds,
                promptedAt: report.promptedAt,
                promptAnswer: report.promptAnswer
            )
            try await post(command)
        } catch {
            keepPauseInputReportIfAbsent(report)
        }
    }

    /// A newer sample for the same pause stays. A failed send only fills an empty slot.
    private func keepPauseInputReportIfAbsent(_ report: PauseInputReport) {
        if pendingPauseReports[report.pauseId] == nil {
            pendingPauseReports[report.pauseId] = report
        }
    }
}
