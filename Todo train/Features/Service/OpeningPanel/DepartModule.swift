//
//  DepartModule.swift
//  Todo train
//
//  DEPART の押し棒。いまは出発ラベルだけ。ロック行・矢羽根などは後続。
//

import SwiftUI

struct DepartModule: View {
    var state: OpeningPanelState
    var onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            OpeningPanelDepartLabel(sunk: state.departBarDepth >= OpeningPanelTiming.departBarSteps)
                .offset(y: departSink)
                .animation(nil, value: state.departBarDepth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("DEPART")
        .accessibilityHint("Hub へ出ます")
        .disabled(state.hasDeparted)
    }

    private var departSink: CGFloat {
        switch state.departBarDepth {
        case 0:
            return 0
        case 1:
            return 1
        case 2:
            return 2
        default:
            return 3
        }
    }
}

#Preview("押し棒") {
    let state = OpeningPanelState(
        scheduler: OpeningPanelDispatchScheduler(),
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: true
    )
    state.pressMaster()
    return OpeningPanelPushBar {
        DepartModule(state: state, onPress: { state.pressDepart() })
    }
    .frame(
        width: OpeningPanelTokens.Chrome.departBar.width,
        height: OpeningPanelTokens.Chrome.departBar.height
    )
    .padding()
    .background(OpeningPanelTokens.Palette.housing)
}