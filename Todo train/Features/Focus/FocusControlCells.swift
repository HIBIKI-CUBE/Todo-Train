//
//  FocusControlCells.swift
//  Todo train
//

import SwiftUI

enum FocusControlLayout {
    static func equalRowHeight(total: CGFloat, rows: Int) -> CGFloat {
        let lines = CGFloat(rows - 1) * FocusPanel.hairlineWidth
        return max((total - lines) / CGFloat(rows), 44)
    }
}

// MARK: - Cell

enum FocusControlProminence {
    case primary
    case secondary
    case tertiary
}

struct FocusControlButton: View {
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

struct FocusControlLabel: View {
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
