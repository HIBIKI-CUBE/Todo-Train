//
//  FocusControlCells.swift
//  Todo train
//

import SwiftUI

enum FocusControlLayout {
    static func equalRowHeight(total: CGFloat, rows: Int) -> CGFloat {
        let lines = CGFloat(rows - 1) * FocusPanel.hairlineWidth
        let available = max(total - lines, 0)
        return available / CGFloat(max(rows, 1))
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
            if compact && prominence == .secondary {
                VStack(spacing: 6) {
                    icon
                    titleText
                }
                .padding(.horizontal, 6)
            } else if compact {
                HStack(spacing: 8) {
                    icon
                    titleText
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
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
        let isCompact = verticalSizeClass == .compact
        return Text(title)
            .font(.system(size: titleSize, weight: .bold, design: .default))
            .lineLimit(isCompact && prominence == .secondary ? 2 : 1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(isCompact ? (prominence == .secondary ? .center : .leading) : .center)
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
        case .secondary: verticalSizeClass == .compact ? 16 : 22
        case .tertiary: verticalSizeClass == .compact ? 17 : 20
        }
    }
}
