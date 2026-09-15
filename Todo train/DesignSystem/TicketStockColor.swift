//
//  TicketStockColor.swift
//  Todo train
//
//  Tag chip hues → Mars paper stock. Untagged keeps the canonical cyan.
//  Classification only — not session state, not dark-mode adaptive.
//

import SwiftUI

enum TicketStockColor {
    struct RGB: Equatable, Sendable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8

        var color: Color {
            Color(
                red: Double(red) / 255,
                green: Double(green) / 255,
                blue: Double(blue) / 255
            )
        }

        init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    struct Stock: Equatable, Sendable {
        var paper: RGB
        var band: RGB
    }

    /// Canonical unused Mars cyan (ref: docs/references/mars-joshaken.png).
    static let untagged = Stock(
        paper: RGB(0xD5, 0xE6, 0xEA),
        band: RGB(0xE7, 0xF1, 0xF3)
    )

    /// Lowest `sortOrder` wins. Empty → nil (untagged stock).
    static func winningColorHex(from tags: [(sortOrder: Int, colorHex: String)]) -> String? {
        tags.min { $0.sortOrder < $1.sortOrder }?.colorHex
    }

    static func winningColorHex(tags: [Tag]) -> String? {
        winningColorHex(from: tags.map { (sortOrder: $0.sortOrder, colorHex: $0.colorHex) })
    }

    static func stock(for colorHex: String?) -> Stock {
        guard let colorHex, !colorHex.isEmpty else { return untagged }
        return table[canonicalHex(colorHex)] ?? untagged
    }

    /// Same hues as `TagPalette.colors`. Paper is high-light / mid-chroma so print ink stays readable.
    private static let table: [String: Stock] = [
        "#888888": Stock(paper: RGB(0xDE, 0xDE, 0xDE), band: RGB(0xE9, 0xE9, 0xE9)),
        "#E5484D": Stock(paper: RGB(0xF8, 0xCC, 0xCE), band: RGB(0xFA, 0xDE, 0xDF)),
        "#F5A524": Stock(paper: RGB(0xFD, 0xE6, 0xC2), band: RGB(0xFC, 0xEF, 0xD8)),
        "#F5D90A": Stock(paper: RGB(0xFD, 0xF5, 0xBB), band: RGB(0xFD, 0xF8, 0xD3)),
        "#30A46C": Stock(paper: RGB(0xC5, 0xE6, 0xD6), band: RGB(0xDA, 0xEF, 0xE4)),
        "#0091FF": Stock(paper: RGB(0xB8, 0xE1, 0xFF), band: RGB(0xD1, 0xEB, 0xFF)),
        "#3E63DD": Stock(paper: RGB(0xC9, 0xD4, 0xF6), band: RGB(0xDC, 0xE3, 0xF9)),
        "#8E4EC6": Stock(paper: RGB(0xE0, 0xCE, 0xEF), band: RGB(0xEB, 0xDF, 0xF5)),
        "#E93D82": Stock(paper: RGB(0xF9, 0xC9, 0xDC), band: RGB(0xFB, 0xDC, 0xE9)),
        "#AD7F58": Stock(paper: RGB(0xE8, 0xDC, 0xD1), band: RGB(0xF0, 0xE8, 0xE0)),
    ]

    private static func canonicalHex(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        return "#\(body.uppercased())"
    }
}
