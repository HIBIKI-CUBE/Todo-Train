//
//  OvertimeControlsView.swift
//  Todo train
//

import SwiftUI

struct OvertimeControlsView: View {
    let onAlreadyDone: () -> Void
    let onJustFinished: () -> Void
    let onExtend: () -> Void

    var body: some View {
        GeometryReader { geo in
            let row = FocusControlLayout.equalRowHeight(total: geo.size.height, rows: 3)
            VStack(spacing: 0) {
                FocusControlButton(
                    title: "もう終わってた",
                    systemImage: "checkmark.circle.fill",
                    fill: TrainTheme.signalGreen,
                    foreground: .black,
                    prominence: .primary,
                    action: onAlreadyDone
                )
                .accessibilityHint("すでに完了していたとして到着します")
                .frame(height: row)

                FocusControlDivider()

                FocusControlButton(
                    title: "ちょうど終わった",
                    systemImage: "flag.checkered",
                    fill: TrainTheme.signalGreen.opacity(0.82),
                    foreground: .black,
                    prominence: .primary,
                    action: onJustFinished
                )
                .accessibilityHint("いま到着として記録します")
                .frame(height: row)

                FocusControlDivider()

                FocusControlButton(
                    title: "延長する",
                    systemImage: "plus",
                    fill: FocusPanel.fillRaised,
                    foreground: FocusPanel.ink,
                    prominence: .secondary,
                    action: onExtend
                )
                .accessibilityHint("見積もり時間を追加します")
                .frame(height: row)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
