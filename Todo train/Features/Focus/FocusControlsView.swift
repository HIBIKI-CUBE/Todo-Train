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

            HStack(spacing: TrainTheme.Space.sm) {
                Button("停車", action: onPause)
                    .buttonStyle(FocusSecondaryButtonStyle(tint: TrainTheme.signalAmber))
                Button("+延長", action: onExtendMenu)
                    .buttonStyle(FocusSecondaryButtonStyle())
            }

            Button("途中下車", action: onPartialDisembark)
                .buttonStyle(FocusSecondaryButtonStyle(tint: TrainTheme.cabinInk.opacity(0.75)))
        }
    }
}
