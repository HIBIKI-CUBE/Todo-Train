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
            VStack(spacing: 2) {
                departFace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("DEPART")
                    .font(.system(size: 7, weight: .regular))
                    .kerning(1.4)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend.opacity(0.84))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("DEPART")
        .accessibilityHint("Hub へ出ます")
        .disabled(state.hasDeparted)
    }

    private var departFace: some View {
        Text("出 発")
            .font(.system(size: 15, weight: .semibold))
            .kerning(5.4)
            .foregroundStyle(departLabelColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(departFaceFill)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .offset(y: departSink)
            .animation(nil, value: state.departBarDepth)
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

    private var departFaceFill: Color {
        state.departBarDepth >= OpeningPanelTiming.departBarSteps
            ? Color(red: 31 / 255, green: 49 / 255, blue: 33 / 255)
            : OpeningPanelTokens.Palette.barFace
    }

    private var departLabelColor: Color {
        state.isPowered
            ? OpeningPanelTokens.Palette.legend
            : OpeningPanelTokens.Palette.legend.opacity(0.4)
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