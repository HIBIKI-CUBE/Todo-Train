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
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button("停車", action: onPause)
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                Button("到着", action: onArrive)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            HStack(spacing: 16) {
                Button("途中下車", action: onPartialDisembark)
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                Button("+延長", action: onExtendMenu)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }
}
