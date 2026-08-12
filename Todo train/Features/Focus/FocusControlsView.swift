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
        GeometryReader { geo in
            let row = equalRowHeight(total: geo.size.height, rows: 3)
            VStack(spacing: 0) {
                FocusControlButton(
                    title: "到着",
                    systemImage: "flag.checkered",
                    fill: TrainTheme.signalGreen,
                    foreground: .black,
                    prominence: .primary,
                    action: onArrive
                )
                .accessibilityHint("切符を到着として閉じ、Hub に戻ります")
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
                        title: "延長",
                        systemImage: "plus",
                        fill: FocusPanel.fillRaised,
                        foreground: FocusPanel.ink,
                        prominence: .secondary,
                        action: onExtendMenu
                    )
                    .accessibilityHint("見積もり時間を追加します。フォーカスは継続します")
                    .frame(maxWidth: .infinity)
                }
                .frame(height: row)

                FocusControlDivider()

                FocusControlButton(
                    title: "途中下車",
                    systemImage: "arrow.turn.up.right",
                    fill: FocusPanel.fill,
                    foreground: FocusPanel.muted,
                    prominence: .tertiary,
                    action: onPartialDisembark
                )
                .accessibilityHint("途中下車して乗り継ぎ切符を掃き出します")
                .frame(height: row)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

struct OvertimeControlsView: View {
    let onAlreadyDone: () -> Void
    let onJustFinished: () -> Void
    let onExtend: () -> Void

    var body: some View {
        GeometryReader { geo in
            let row = equalRowHeight(total: geo.size.height, rows: 3)
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

private func equalRowHeight(total: CGFloat, rows: Int) -> CGFloat {
    let lines = CGFloat(rows - 1) * FocusPanel.hairlineWidth
    return max((total - lines) / CGFloat(rows), 44)
}

// MARK: - Cell

private enum FocusControlProminence {
    case primary
    case secondary
    case tertiary
}

private struct FocusControlButton: View {
    let title: String
    let systemImage: String
    let fill: Color
    let foreground: Color
    let prominence: FocusControlProminence
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FocusControlLabel(
                title: title,
                systemImage: systemImage,
                prominence: prominence
            )
        }
        .buttonStyle(FocusControlCellStyle(fill: fill, foreground: foreground))
        .accessibilityLabel(title)
    }
}

private struct FocusControlLabel: View {
    let title: String
    let systemImage: String
    let prominence: FocusControlProminence

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let compact = verticalSizeClass == .compact
        Group {
            if compact {
                HStack(spacing: 12) {
                    icon
                    titleText
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    icon
                    titleText
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .bold))
            .symbolRenderingMode(.monochrome)
            .frame(width: iconSize + 4, height: iconSize + 4)
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: titleSize, weight: .bold, design: .default))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var iconSize: CGFloat {
        switch prominence {
        case .primary: verticalSizeClass == .compact ? 22 : 28
        case .secondary: verticalSizeClass == .compact ? 20 : 24
        case .tertiary: verticalSizeClass == .compact ? 18 : 22
        }
    }

    private var titleSize: CGFloat {
        switch prominence {
        case .primary: verticalSizeClass == .compact ? 20 : 24
        case .secondary: verticalSizeClass == .compact ? 18 : 22
        case .tertiary: verticalSizeClass == .compact ? 17 : 20
        }
    }
}

// MARK: - Extend panel (dashboard-matched)

struct FocusExtendPanel: View {
    let reasons: [String]
    @Binding var selectedReason: String?
    let onExtend: (Int) -> Void
    let onDismiss: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let minuteOptions = EstimateChips.extendPresets

    var body: some View {
        GeometryReader { geo in
            if verticalSizeClass == .compact {
                compactLayout(size: geo.size)
            } else {
                portraitLayout(size: geo.size)
            }
        }
    }

    private func portraitLayout(size: CGSize) -> some View {
        let headerH: CGFloat = 44
        let remaining = max(size.height - headerH - FocusPanel.hairlineWidth, 1)
        let minuteRow = remaining * 0.42
        let reasonRow = remaining - minuteRow - FocusPanel.hairlineWidth

        return VStack(spacing: 0) {
            extendHeader
                .frame(height: headerH)

            FocusControlDivider()

            minuteRowView
                .frame(height: minuteRow)

            FocusControlDivider()

            reasonGrid
                .frame(height: max(reasonRow, 0))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func compactLayout(size: CGSize) -> some View {
        let headerH: CGFloat = 40
        let bodyH = max(size.height - headerH - FocusPanel.hairlineWidth, 1)

        return VStack(spacing: 0) {
            extendHeader
                .frame(height: headerH)

            FocusControlDivider()

            minuteRowView
                .frame(height: bodyH)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var extendHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
            Text("延長")
                .font(.system(size: 17, weight: .bold))
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Text("戻る")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FocusPanel.ink)
        }
        .padding(.leading, 16)
        .foregroundStyle(FocusPanel.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusPanel.fill)
    }

    private var minuteRowView: some View {
        HStack(spacing: 0) {
            ForEach(Array(minuteOptions.enumerated()), id: \.element) { index, minutes in
                if index > 0 {
                    FocusControlVerticalDivider()
                }
                Button {
                    onExtend(minutes)
                } label: {
                    VStack(spacing: 6) {
                        Text("+\(minutes)")
                            .font(.system(size: verticalSizeClass == .compact ? 28 : 34, weight: .bold, design: .default))
                            .monospacedDigit()
                        Text("分")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FocusPanel.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(FocusPanel.ink)
                }
                .buttonStyle(FocusControlCellStyle(fill: FocusPanel.fillRaised, foreground: FocusPanel.ink))
                .accessibilityLabel("\(minutes)分延長")
            }
        }
    }

    private var reasonGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 0),
            GridItem(.flexible(), spacing: 0)
        ]
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(reasons.enumerated()), id: \.element) { index, reason in
                let selected = selectedReason == reason
                Button {
                    selectedReason = selected ? nil : reason
                } label: {
                    Text(reason)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 8)
                        .foregroundStyle(selected ? TrainTheme.signalAmber : FocusPanel.ink)
                        .background(selected ? TrainTheme.signalAmber.opacity(0.18) : FocusPanel.fill)
                        .overlay(alignment: .top) {
                            if index >= 2 {
                                Rectangle()
                                    .fill(FocusPanel.hairline)
                                    .frame(height: FocusPanel.hairlineWidth)
                            }
                        }
                        .overlay(alignment: .leading) {
                            if index % 2 == 1 {
                                Rectangle()
                                    .fill(FocusPanel.hairline)
                                    .frame(width: FocusPanel.hairlineWidth)
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 52)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FocusPanel.fill)
    }
}
