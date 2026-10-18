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
            let row = FocusControlLayout.equalRowHeight(total: geo.size.height, rows: 4)
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

                HStack(spacing: 0) {
                    FocusControlButton(
                        title: "現在位置",
                        systemImage: "antenna.radiowaves.left.and.right",
                        fill: FocusPanel.fillRaised,
                        foreground: FocusPanel.ink,
                        prominence: .secondary,
                        action: onReestimate
                    )
                    .accessibilityHint("いま何割の地点かを指令に報告します")
                    .frame(maxWidth: .infinity)

                    FocusControlVerticalDivider()

                    FocusControlButton(
                        title: "割り込み",
                        systemImage: "rectangle.stack.badge.plus",
                        fill: FocusPanel.fillRaised,
                        foreground: FocusPanel.ink,
                        prominence: .secondary,
                        action: onInterrupt
                    )
                    .accessibilityHint("割り込みの切符を発行します")
                    .frame(maxWidth: .infinity)
                }
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
            .environment(\.verticalSizeClass, .compact)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .clipped()
        }
    }
}
