//
//  FocusExtendPanel.swift
//  Todo train
//

import SwiftUI

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
