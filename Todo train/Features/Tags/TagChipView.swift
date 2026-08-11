//
//  TagChipView.swift
//  Todo train
//

import SwiftUI

struct TagChipView: View {
    let name: String
    let colorHex: String
    var isSelected: Bool = true
    var isHighlighted: Bool = false

    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isSelected ? Color.white : TagPalette.color(hex: colorHex))
            .background(
                Capsule()
                    .fill(isSelected ? TagPalette.color(hex: colorHex) : TagPalette.color(hex: colorHex).opacity(0.15))
            )
            .overlay {
                if isHighlighted && !isSelected {
                    Capsule()
                        .strokeBorder(TagPalette.color(hex: colorHex), lineWidth: 1.5)
                }
            }
    }
}

struct TagChipRow: View {
    let tags: [Tag]
    var maxVisible: Int = 2

    private var ordered: [Tag] {
        TagOrdering.sortedByOrder(tags)
    }

    var body: some View {
        let visible = Array(ordered.prefix(maxVisible))
        let overflow = ordered.count - visible.count
        HStack(spacing: 4) {
            ForEach(visible, id: \.id) { tag in
                TagChipView(name: tag.name, colorHex: tag.colorHex)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
