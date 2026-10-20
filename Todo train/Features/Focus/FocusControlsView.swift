//
//  FocusControlsView.swift
//  Todo train
//

import SwiftUI

struct FocusControlsView: View {
    let onPause: () -> Void
    let onReserve: () -> Void
    let onArrive: () -> Void
    let onReestimate: () -> Void
    let onInterrupt: () -> Void
    var showsReserve: Bool = true

    var body: some View {
        GeometryReader { geo in
            let row = FocusControlLayout.equalRowHeight(total: geo.size.height, rows: 3)
            VStack(spacing: 0) {
                FocusControlButton(
                    title: "到着",
                    systemImage: "flag.checkered",
                    fill: TrainTheme.signalGreen,
                    foreground: .black,
                    prominence: .primary,
                    action: onArrive
                )
                .accessibilityHint("切符を到着として閉じ、Hub を開きます")
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
                    .accessibilityHint("セッションを停車し、Hub を開きます。Live Activity から再乗車できます。")
                    .frame(maxWidth: .infinity)

                    FocusControlVerticalDivider()

                    FocusControlButton(
                        title: "位置確認",
                        systemImage: "scope",
                        fill: FocusPanel.fillRaised,
                        foreground: FocusPanel.ink,
                        prominence: .secondary,
                        action: onReestimate
                    )
                    .accessibilityHint("いまの地点から、着の見込みを確かめます。")
                    .frame(maxWidth: .infinity)
                }
                .frame(height: row)

                FocusControlDivider()

                HStack(spacing: 0) {
                    FocusControlButton(
                        title: "割り込み",
                        systemImage: "rectangle.stack.badge.plus",
                        fill: FocusPanel.fillRaised,
                        foreground: FocusPanel.ink,
                        prominence: .secondary,
                        action: onInterrupt
                    )
                    .accessibilityHint("新しい切符を発行し、今の切符を停車して発車します")
                    .frame(maxWidth: .infinity)

                    if showsReserve {
                        FocusControlVerticalDivider()

                        FocusControlButton(
                            title: "予約",
                            systemImage: "bookmark",
                            fill: FocusPanel.fill,
                            foreground: FocusPanel.ink,
                            prominence: .secondary,
                            action: onReserve
                        )
                        .accessibilityHint("次の一本の予約欄を開きます。乗車は始まりません。")
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: row)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
