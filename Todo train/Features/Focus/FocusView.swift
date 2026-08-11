//
//  FocusView.swift
//  Todo train
//

import SwiftData
import SwiftUI

struct FocusView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings

    @State private var showExtendChips = false
    @State private var showPauseLimitSheet = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var didPlayOvertimeSound = false
    @State private var overtimePulse = false
    @State private var canvasLaunch: CanvasLaunch?

    private struct CanvasLaunch: Identifiable {
        let id = UUID()
        let parent: Ticket
        let sessionID: UUID?
    }

    var body: some View {
        ZStack {
            CabinBackground(overtime: sessionManager.phase == .overtime)

            VStack(spacing: TrainTheme.Space.xl) {
                Spacer()

                Text(title)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(TrainTheme.cabinInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TrainTheme.Space.lg)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let _ = context.date
                    let remaining = sessionManager.remainingSeconds
                    VStack(spacing: TrainTheme.Space.sm) {
                        Text(timerLabel(remaining))
                            .font(TrainTheme.TypeScale.timer())
                            .monospacedDigit()
                            .foregroundStyle(timerColor(remaining))
                            .scaleEffect(overtimePulse ? 1.03 : 1)
                            .animation(TrainTheme.Motion.pulse, value: overtimePulse)

                        if let budget = sessionManager.activeSession?.budgetSecondsAtStart,
                           let estimate = sessionManager.activeSession?.estimatedSecondsAtStart {
                            let extensionMinutes = max(0, (budget - estimate) / 60)
                            Text(
                                extensionMinutes > 0
                                    ? "見積もり \(estimate / 60)分  ·  延長 +\(extensionMinutes)分"
                                    : "見積もり \(estimate / 60)分"
                            )
                            .font(TrainTheme.TypeScale.timerMeta())
                            .foregroundStyle(TrainTheme.cabinInk.opacity(0.55))
                        }
                    }
                    .onChange(of: context.date) { _, _ in
                        sessionManager.reconcile()
                        handleOvertimeSound()
                    }
                }

                Spacer()

                if showExtendChips {
                    VStack(spacing: TrainTheme.Space.sm) {
                        Text("どのくらい伸ばしますか？")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TrainTheme.cabinInk.opacity(0.7))
                        EstimateChips(style: .extendPrefix) { minutes in
                            run { try sessionManager.extend(by: TimeInterval(minutes * 60)) }
                            showExtendChips = false
                        }
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                FocusControlsView(
                    onPause: {
                        run {
                            try sessionManager.pause()
                        }
                    },
                    onPartialDisembark: {
                        partialDisembarkAndShowCanvas()
                    },
                    onArrive: {
                        run { try sessionManager.arrive() }
                    },
                    onExtendMenu: {
                        withAnimation(TrainTheme.Motion.soft) {
                            showExtendChips.toggle()
                        }
                    }
                )
                .padding(.horizontal, TrainTheme.Space.lg)
                .padding(.bottom, 36)
            }

            if sessionManager.phase == .overtime {
                OvertimeOverlay(
                    onAlreadyDone: { run { try sessionManager.arrive() } },
                    onJustFinished: { run { try sessionManager.arrive() } },
                    onExtend: { seconds in
                        run { try sessionManager.extend(by: seconds) }
                    }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showPauseLimitSheet) {
            PauseLimitSheet(
                onCurrentPartialDisembark: { ticket, sessionID in
                    canvasLaunch = CanvasLaunch(parent: ticket, sessionID: sessionID)
                },
                onSlotFreedTryPause: {
                    try? sessionManager.pause()
                }
            )
            .environment(sessionManager)
        }
        .sheet(item: $canvasLaunch) { launch in
            RemainingTicketsCanvas(parent: launch.parent, fromSessionID: launch.sessionID)
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            sessionManager.reconcile()
            handleOvertimeSound()
        }
        .onChange(of: sessionManager.phase) { _, newPhase in
            if newPhase != .overtime {
                didPlayOvertimeSound = false
                overtimePulse = false
            } else {
                overtimePulse = true
                handleOvertimeSound()
            }
        }
    }

    private var title: String {
        sessionManager.activeSession?.ticket?.title ?? "乗務中"
    }

    private func timerLabel(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        if total < 0 {
            let absTotal = abs(total)
            return String(format: "超過 %d:%02d", absTotal / 60, absTotal % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func timerColor(_ remaining: TimeInterval) -> Color {
        if remaining < 0 { return TrainTheme.signalRed }
        if remaining < 60 { return TrainTheme.signalAmber }
        return TrainTheme.cabinInk
    }

    private func handleOvertimeSound() {
        guard settings.overtimeSoundEnabled else { return }
        guard sessionManager.phase == .overtime, !didPlayOvertimeSound else { return }
        didPlayOvertimeSound = true
        OvertimeOverlay.playAlertSound()
    }

    private func partialDisembarkAndShowCanvas() {
        guard let ticket = sessionManager.activeSession?.ticket else { return }
        let sessionID = sessionManager.activeSession?.id
        do {
            try sessionManager.partialDisembark()
            canvasLaunch = CanvasLaunch(parent: ticket, sessionID: sessionID)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func run(_ body: () throws -> Void) {
        do {
            try body()
        } catch let error as SessionError where error == .pauseLimitReached {
            showPauseLimitSheet = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    let container = try! AppModelContainer.make(inMemory: true)
    let context = container.mainContext
    let manager = SessionManager(modelContext: context)
    try! manager.startService()
    let ticket = Ticket(title: "プレビュー切符", estimatedSeconds: 90)
    context.insert(ticket)
    try! manager.board(ticket: ticket)
    return FocusView()
        .environment(manager)
        .environment(AppSettings.shared)
}
