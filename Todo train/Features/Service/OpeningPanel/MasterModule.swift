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
        VStack(alignment: .leading, spacing: 4) {
            Text("MASTER")
                .font(.system(size: 7, weight: .regular))
                .kerning(1.4)
                .foregroundStyle(OpeningPanelTokens.Palette.legend)

            HStack(alignment: .center, spacing: 6) {
                keySwitch
                    .frame(width: 58, height: 60)

                lens
                    .frame(width: 40, height: 40)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                Text("PWR")
                    .font(.system(size: 7, weight: .regular))
                    .kerning(1.4)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend)
                powerLEDRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(nil, value: keyDegrees)
        .onAppear {
            keyDegrees = state.isPowered ? 45 : -45
        }
        .onChange(of: state.isPowered) { _, isPowered in
            runKeySteps(poweringOn: isPowered)
        }
    }

    private var keySwitch: some View {
        Button(action: onPress) {
            ZStack(alignment: .top) {
                Text("OFF")
                    .font(.system(size: 7, weight: .regular))
                    .kerning(1.4)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("ON")
                    .font(.system(size: 7, weight: .regular))
                    .kerning(1.4)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 2)

                tickMarks

                Circle()
                    .fill(Color(red: 26 / 255, green: 27 / 255, blue: 28 / 255))
                    .overlay {
                        Circle()
                            .strokeBorder(Color(red: 93 / 255, green: 97 / 255, blue: 101 / 255), lineWidth: 2)
                        Circle()
                            .strokeBorder(Color(red: 35 / 255, green: 36 / 255, blue: 38 / 255), lineWidth: 3)
                            .padding(2)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
                    .overlay {
                        keyBlade
                    }
                    .frame(width: 42, height: 42)
                    .offset(y: 14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isPowered ? "MASTER ON" : "MASTER OFF")
        .accessibilityHint("運行の電源を入れます")
    }

    private var tickMarks: some View {
        ZStack {
            Rectangle()
                .fill(OpeningPanelTokens.Palette.legend)
                .frame(width: 1, height: 5)
                .rotationEffect(.degrees(-45))
                .offset(x: -17, y: 11)
            Rectangle()
                .fill(OpeningPanelTokens.Palette.legend)
                .frame(width: 1, height: 5)
                .rotationEffect(.degrees(45))
                .offset(x: 17, y: 11)
        }
    }

    private var keyBlade: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 139 / 255, green: 143 / 255, blue: 147 / 255))
                .frame(width: 12, height: 34)
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(red: 58 / 255, green: 60 / 255, blue: 63 / 255))
                        .frame(width: 2, height: 8)
                        .offset(x: 5, y: 3)
                }
                .shadow(color: Color(red: 14 / 255, green: 14 / 255, blue: 15 / 255), radius: 0, y: 1)
        }
        .rotationEffect(.degrees(keyDegrees))
    }

    private var lens: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 85 / 255, green: 88 / 255, blue: 91 / 255))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color(red: 46 / 255, green: 48 / 255, blue: 51 / 255), lineWidth: 3)
                }

            VStack(spacing: 2) {
                Text("STBY")
                    .opacity(state.isPowered ? 0.35 : 1)
                Text("ON")
                    .opacity(state.isPowered ? 1 : 0.35)
            }
            .font(.system(size: 7, weight: .regular))
            .kerning(1.4)
            .foregroundStyle(OpeningPanelTokens.TimetableChrome.amberSolid)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.isPowered ? "ON" : "STBY")
    }

    private var powerLEDRow: some View {
        HStack(spacing: 2) {
            ForEach(0..<OpeningPanelTiming.ledCount, id: \.self) { index in
                let lit = index < litLEDCount
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? OpeningPanelTokens.Palette.amber : OpeningPanelTokens.Palette.amberDim)
                    .frame(height: 9)
                    .shadow(
                        color: lit ? OpeningPanelTokens.Palette.amber.opacity(0.45) : .clear,
                        radius: 2
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PWR \(litLEDCount) / \(OpeningPanelTiming.ledCount)")
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
                .padding(8)
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

private final class OpeningPanelFeedbackSilent: OpeningPanelFeedback {
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