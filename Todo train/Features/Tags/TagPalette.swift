//
//  TagPalette.swift
//  Todo train
//

import SwiftUI

enum TagPalette {
    static let colors: [(name: String, hex: String)] = [
        ("灰", "#888888"),
        ("赤", "#E5484D"),
        ("橙", "#F5A524"),
        ("黄", "#F5D90A"),
        ("緑", "#30A46C"),
        ("青", "#0091FF"),
        ("藍", "#3E63DD"),
        ("紫", "#8E4EC6"),
        ("桃", "#E93D82"),
        ("茶", "#AD7F58"),
    ]

    static func color(hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return Color.gray
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

enum TagOrdering {
    /// Reassigns contiguous sortOrder from 0 based on the given order.
    static func normalizeSortOrders(_ tags: [Tag]) {
        for (index, tag) in tags.enumerated() {
            tag.sortOrder = index
        }
    }

    static func sortedByOrder(_ tags: [Tag]) -> [Tag] {
        tags.sorted { $0.sortOrder < $1.sortOrder }
    }
}
