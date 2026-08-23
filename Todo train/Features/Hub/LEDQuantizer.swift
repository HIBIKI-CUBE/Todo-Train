//
//  LEDQuantizer.swift
//  Todo train
//
//  Coarse but readable LED kanji:
//  take the real glyph path, then light a cell only if its center is inside.
//  Coverage-averaging fattens strokes and closes counters (車's 田, 発's 癶).
//

import CoreGraphics
import CoreText
import UIKit

enum LEDQuantizer {
    /// 16 is the station-board grain. Readability comes from center sampling, not more cells.
    static let kanjiSize = 16
    static let supersample = 8
    static let coverageThreshold: CGFloat = 0.5
    /// Leave ~1 LED of margin so 癶 / 田 don't clip.
    static let fontFillRatio: CGFloat = 0.84
    /// W6 merged strokes. W3 dropped 発's 癶. W4 keeps both counters and the hat.
    static let preferredFontName = "HiraginoSans-W4"

    static func quantize(
        coverage: [CGFloat],
        columns: Int,
        rows: Int,
        threshold: CGFloat = coverageThreshold
    ) -> LEDMatrix.Glyph {
        precondition(columns > 0 && columns <= 32)
        precondition(rows > 0)
        precondition(coverage.count == columns * rows)
        var bits = [UInt32]()
        bits.reserveCapacity(rows)
        for row in 0..<rows {
            var line: UInt32 = 0
            for col in 0..<columns {
                if coverage[row * columns + col] >= threshold {
                    line |= 1 << (columns - 1 - col)
                }
            }
            bits.append(line)
        }
        return LEDMatrix.Glyph(width: columns, height: rows, rows: bits)
    }

    static func glyph(
        for text: String,
        columns: Int = kanjiSize,
        rows: Int = kanjiSize,
        fontFillRatio: CGFloat = fontFillRatio,
        fontName: String? = nil
    ) -> LEDMatrix.Glyph {
        let path = fittedGlyphPath(
            for: text,
            columns: columns,
            rows: rows,
            fontFillRatio: fontFillRatio,
            fontName: fontName
        )
        var coverage = [CGFloat](repeating: 0, count: columns * rows)
        if let path {
            for row in 0..<rows {
                for col in 0..<columns {
                    let point = CGPoint(x: CGFloat(col) + 0.5, y: CGFloat(row) + 0.5)
                    if path.contains(point, using: .winding) {
                        coverage[row * columns + col] = 1
                    }
                }
            }
        }
        return dropSpecks(quantize(coverage: coverage, columns: columns, rows: rows, threshold: 0.5))
    }

    /// Used by tests to lock the threshold rule. Kanji rendering uses `glyph(for:)` (path centers).
    static func coverage(
        for text: String,
        columns: Int,
        rows: Int,
        supersample: Int = supersample,
        fontFillRatio: CGFloat = fontFillRatio,
        fontName: String? = nil
    ) -> [CGFloat] {
        let width = columns * supersample
        let height = rows * supersample
        let count = width * height
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        bytes.initialize(repeating: 0, count: count)
        defer {
            bytes.deinitialize(count: count)
            bytes.deallocate()
        }

        guard let ctx = CGContext(
            data: bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return Array(repeating: 0, count: columns * rows)
        }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldAntialias(true)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        let font = kanjiFont(name: fontName, size: CGFloat(height) * fontFillRatio)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ]
        let nsText = text as NSString
        let textSize = nsText.size(withAttributes: attrs)
        let rect = CGRect(
            x: 0,
            y: (CGFloat(height) - textSize.height) / 2,
            width: CGFloat(width),
            height: textSize.height
        )
        UIGraphicsPushContext(ctx)
        nsText.draw(in: rect, withAttributes: attrs)
        UIGraphicsPopContext()

        let cellArea = CGFloat(supersample * supersample * 255)
        var result = [CGFloat](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            for col in 0..<columns {
                var sum = 0
                let y0 = row * supersample
                let x0 = col * supersample
                for dy in 0..<supersample {
                    let rowStart = (y0 + dy) * width + x0
                    for dx in 0..<supersample {
                        sum += Int(bytes[rowStart + dx])
                    }
                }
                result[row * columns + col] = CGFloat(sum) / cellArea
            }
        }
        return result
    }

    /// Map the glyph outline into LED space (origin top-left, one unit per cell).
    private static func fittedGlyphPath(
        for text: String,
        columns: Int,
        rows: Int,
        fontFillRatio: CGFloat,
        fontName: String?
    ) -> CGPath? {
        let uiFont = kanjiFont(name: fontName, size: 1000)
        let ctFont = CTFontCreateWithName(uiFont.fontName as CFString, uiFont.pointSize, nil)
        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(ctFont, chars, &glyphs, chars.count),
              let first = glyphs.first,
              let raw = CTFontCreatePathForGlyph(ctFont, first, nil)
        else {
            return nil
        }

        let bbox = raw.boundingBoxOfPath
        guard bbox.width > 0, bbox.height > 0 else { return nil }

        let margin = (1 - fontFillRatio) / 2
        let target = CGRect(
            x: CGFloat(columns) * margin,
            y: CGFloat(rows) * margin,
            width: CGFloat(columns) * fontFillRatio,
            height: CGFloat(rows) * fontFillRatio
        )
        let scale = min(target.width / bbox.width, target.height / bbox.height)
        // Font space is y-up. LED cells are y-down. Center the bbox in `target`, then flip.
        var transform = CGAffineTransform(translationX: -bbox.midX, y: -bbox.midY)
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(
            CGAffineTransform(translationX: target.midX, y: CGFloat(rows) - target.midY)
        )
        transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        transform = transform.concatenating(CGAffineTransform(translationX: 0, y: CGFloat(rows)))
        return raw.copy(using: &transform)
    }

    /// Drop salt pixels so a coarse grid doesn't grow speckle.
    private static func dropSpecks(_ glyph: LEDMatrix.Glyph) -> LEDMatrix.Glyph {
        var rows = glyph.rows
        for row in 0..<glyph.height {
            for col in 0..<glyph.width {
                guard glyph.pixel(row: row, col: col) else { continue }
                let neighbors =
                    (glyph.pixel(row: row - 1, col: col) ? 1 : 0)
                    + (glyph.pixel(row: row + 1, col: col) ? 1 : 0)
                    + (glyph.pixel(row: row, col: col - 1) ? 1 : 0)
                    + (glyph.pixel(row: row, col: col + 1) ? 1 : 0)
                if neighbors == 0 {
                    rows[row] &= ~(1 << (glyph.width - 1 - col))
                }
            }
        }
        return LEDMatrix.Glyph(width: glyph.width, height: glyph.height, rows: rows)
    }

    private static func kanjiFont(name: String?, size: CGFloat) -> UIFont {
        if let name, let font = UIFont(name: name, size: size) {
            return font
        }
        return UIFont(name: preferredFontName, size: size)
            ?? UIFont(name: "HiraginoSans-W4", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .regular)
    }
}
