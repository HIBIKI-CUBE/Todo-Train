//
//  MasterModule.swift
//  Todo train
//
//  MASTER キースイッチと PWR の LED 6 個。状態は OpeningPanelState を読むだけ。
//

import SwiftUI

struct MasterModule: View {
    var state: OpeningPanelState
    var onPress: () -> Void

    @State private var keyDegrees: Double = -45
    @State private var keyStepTask: Task<Void, Never>?

    private var litLEDCount: Int {
        switch state.lampCheck {
        case .allOn:
            return OpeningPanelTiming.ledCount
        case .off:
            return 0
        case .done:
            return state.powerLEDCount
        }
    }

    var body: some View {
        OpeningPanelMasterAssembly(
            powered: state.isPowered,
            keyDegrees: keyDegrees,
            litLEDCount: litLEDCount,
            standbyAvailable: !state.isPowered,
            onPress: onPress
        )
        .animation(nil, value: keyDegrees)
        .onAppear {
            keyDegrees = state.isPowered ? 45 : -45
        }
        .onChange(of: state.isPowered) { _, isPowered in
            runKeySteps(poweringOn: isPowered)
        }
    }

    private func runKeySteps(poweringOn: Bool) {
        let steps: [(TimeInterval, Double)] = poweringOn
            ? [(0, -15), (0.035, 15), (0.070, 45)]
            : [(0, 15), (0.035, -15), (0.070, -45)]
        keyStepTask?.cancel()
        keyStepTask = Task { @MainActor in
            var lastDelay: TimeInterval = 0
            for (delay, angle) in steps {
                let wait = max(0, delay - lastDelay)
                lastDelay = delay
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                if Task.isCancelled { return }
                withTransaction(Transaction(animation: nil)) {
                    keyDegrees = angle
                }
            }
        }
    }
}

private struct MasterModulePreviewPanel: View {
    let state: OpeningPanelState

    var body: some View {
        let frame = OpeningPanelTokens.Module.master.frame()
        OpeningPanelModule(tone: .upper) {
            MasterModule(state: state, onPress: { state.pressMaster() })
        }
        .frame(width: frame.width, height: frame.height)
        .background(OpeningPanelTokens.Palette.housing)
    }
}

#Preview("OFF") {
    let state = OpeningPanelState(
        scheduler: OpeningPanelDispatchScheduler(),
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: true
    )
    return MasterModulePreviewPanel(state: state)
}

#Preview("全灯チェック中") {
    let state = OpeningPanelState(
        scheduler: OpeningPanelDispatchScheduler(),
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: true
    )
    state.pressMaster()
    return MasterModulePreviewPanel(state: state)
}

#Preview("LED 3 段") {
    let scheduler = OpeningPanelPreviewScheduler()
    let state = OpeningPanelState(
        scheduler: scheduler,
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: false
    )
    state.pressMaster()
    scheduler.advance(by: OpeningPanelTiming.lampCheck)
    scheduler.advance(by: OpeningPanelTiming.powerLEDStep)
    scheduler.advance(by: OpeningPanelTiming.powerLEDStep)
    return MasterModulePreviewPanel(state: state)
}

#Preview("ON") {
    let scheduler = OpeningPanelPreviewScheduler()
    let state = OpeningPanelState(
        scheduler: scheduler,
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: false
    )
    state.pressMaster()
    scheduler.finishPowerSequence()
    return MasterModulePreviewPanel(state: state)
}

final class OpeningPanelFeedbackSilent: OpeningPanelFeedback {
    func play(_ cue: OpeningPanelCue) {}
}

@MainActor
private final class OpeningPanelPreviewScheduler: OpeningPanelScheduling {
    private struct Item {
        var id: Int
        var due: TimeInterval
        var action: () -> Void
    }

    private var now: TimeInterval = 0
    private var nextID = 0
    private var items: [Item] = []

    func schedule(after seconds: TimeInterval, execute: @escaping () -> Void) -> OpeningPanelTask {
        let id = nextID
        nextID += 1
        items.append(Item(id: id, due: now + seconds, action: execute))
        return OpeningPanelTask { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let index = items.indices.min(by: { items[$0].due < items[$1].due }),
              items[index].due <= target {
            let item = items.remove(at: index)
            now = item.due
            item.action()
        }
        now = target
    }

    func finishPowerSequence() {
        advance(by: OpeningPanelTiming.lampCheck)
        for _ in 1...OpeningPanelTiming.ledCount {
            advance(by: OpeningPanelTiming.powerLEDStep)
        }
        advance(by: OpeningPanelTiming.powerLEDSettle)
    }
}