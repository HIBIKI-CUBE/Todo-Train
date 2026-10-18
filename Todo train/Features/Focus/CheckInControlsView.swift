//
//  CheckInControlsView.swift
//  Todo train
//

import SwiftUI
import TodoTrainSync

struct CheckInControlsView: View {
    let prompt: String
    let onStillOnIt: () -> Void
    let onReestimate: () -> Void

    var body: some View {
        GeometryReader { geo in
            let row = FocusControlLayout.equalRowHeight(total: geo.size.height, rows: 2)
            VStack(spacing: 0) {
                FocusControlButton(
                    title: CabinCopy.still,
                    systemImage: "tram.fill",
                    fill: TrainTheme.signalGreen,
                    foreground: .black,
                    prominence: .primary,
                    action: onStillOnIt
                )
                .accessibilityHint(prompt)
                .frame(height: row)

                FocusControlDivider()

                FocusControlButton(
                    title: "現在位置",
                    systemImage: "antenna.radiowaves.left.and.right",
                    fill: FocusPanel.fillRaised,
                    foreground: FocusPanel.ink,
                    prominence: .secondary,
                    action: onReestimate
                )
                .accessibilityHint("いま何割の地点かを指令に報告します")
                .frame(height: row)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
