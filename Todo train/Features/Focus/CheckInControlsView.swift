//
//  CheckInControlsView.swift
//  Todo train
//

import SwiftUI

struct CheckInControlsView: View {
    let prompt: String
    let onStillOnIt: () -> Void
    let onPause: () -> Void
    let onAlreadyDone: () -> Void
    let onWillExtend: () -> Void

    var body: some View {
        GeometryReader { geo in
            let row = FocusControlLayout.equalRowHeight(total: geo.size.height, rows: 3)
            VStack(spacing: 0) {
                FocusControlButton(
                    title: "まだこれ",
                    systemImage: "tram.fill",
                    fill: TrainTheme.signalGreen,
                    foreground: .black,
                    prominence: .primary,
                    action: onStillOnIt
                )
                .accessibilityHint(prompt)
                .frame(height: row)

                FocusControlDivider()

                HStack(spacing: 0) {
                    FocusControlButton(
                        title: "停車",
                        systemImage: "pause.fill",
                        fill: FocusPanel.fillRaised,
                        foreground: TrainTheme.signalAmber,
                        prominence: .secondary,
                        action: onPause
                    )
                    .accessibilityHint("セッションを停車し、Hub に戻ります")
                    .frame(maxWidth: .infinity)

                    FocusControlVerticalDivider()

                    FocusControlButton(
                        title: "延長しそう",
                        systemImage: "plus",
                        fill: FocusPanel.fillRaised,
                        foreground: FocusPanel.ink,
                        prominence: .secondary,
                        action: onWillExtend
                    )
                    .accessibilityHint("見積もり時間を追加します")
                    .frame(maxWidth: .infinity)
                }
                .frame(height: row)

                FocusControlDivider()

                FocusControlButton(
                    title: "もう終わってた",
                    systemImage: "checkmark.circle.fill",
                    fill: TrainTheme.signalGreen.opacity(0.82),
                    foreground: .black,
                    prominence: .primary,
                    action: onAlreadyDone
                )
                .accessibilityHint("すでに完了していたとして到着します")
                .frame(height: row)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
