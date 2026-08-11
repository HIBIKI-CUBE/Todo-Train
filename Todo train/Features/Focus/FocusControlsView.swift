//
//  FocusControlsView.swift
//  Todo train
//

import SwiftUI

struct FocusControlsView: View {
    let onPause: () -> Void
    let onPartialDisembark: () -> Void
    let onArrive: () -> Void
    let onExtendMenu: () -> Void

    var body: some View {
        VStack(spacing: TrainTheme.Space.sm) {
            Button("到着", action: onArrive)
                .buttonStyle(FocusPrimaryButtonStyle())
                .accessibilityHint("切符を到着として閉じ、Hub に戻ります")

            HStack(spacing: TrainTheme.Space.sm) {
                Button("停車", action: onPause)
                    .buttonStyle(FocusSecondaryButtonStyle(tint: TrainTheme.signalAmber))
                    .accessibilityHint("セッションを停車し、Hub に戻ります")
                Button("+延長", action: onExtendMenu)
                    .buttonStyle(FocusSecondaryButtonStyle())
                    .accessibilityHint("見積もり時間を追加します。フォーカスは継続します")
            }

            Button("途中下車", action: onPartialDisembark)
                .buttonStyle(FocusSecondaryButtonStyle(tint: TrainTheme.cabinInk.opacity(0.75)))
                .accessibilityHint("途中下車して乗り継ぎ切符を掃き出します")
        }
    }
}
