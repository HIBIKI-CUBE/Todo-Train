//
//  OvertimeControlsView.swift
//  Todo train
//

import SwiftUI

struct OvertimeControlsView: View {
    let onAlreadyDone: () -> Void
    let onJustFinished: () -> Void
    let onReestimate: () -> Void
    let onInterrupt: () -> Void
    let onPause: () -> Void

    var body: some View {
        GeometryReader { geo in
            let row = FocusControlLayout.equalRowHeight(total: geo.size.height, rows: 5)
            VStack(spacing: 0) {
                FocusControlButton(
                    title: "到着済み",
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
                    title: "いま到着",
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
                    title: "見積もり直す",
                    systemImage: "slider.horizontal.3",
                    fill: FocusPanel.fillRaised,
                    foreground: FocusPanel.ink,
                    prominence: .secondary,
                    action: onReestimate
                )
                .accessibilityHint("進捗から見積もりを直します")
                .frame(height: row)

                FocusControlDivider()

                FocusControlButton(
                    title: "割り込みが入った",
                    systemImage: "rectangle.stack.badge.plus",
                    fill: FocusPanel.fillRaised,
                    foreground: FocusPanel.ink,
                    prominence: .secondary,
                    action: onInterrupt
                )
                .accessibilityHint("割り込みの切符を発行します")
                .frame(height: row)

                FocusControlDivider()

                FocusControlButton(
                    title: "停車",
                    systemImage: "pause.fill",
                    fill: FocusPanel.fillRaised,
                    foreground: TrainTheme.signalAmber,
                    prominence: .secondary,
                    action: onPause
                )
                .accessibilityHint("いったん停車します")
                .frame(height: row)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
