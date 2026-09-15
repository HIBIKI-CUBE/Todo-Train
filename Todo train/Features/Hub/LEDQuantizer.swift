//
//  LEDQuantizer.swift
//  Todo train
//
//  Station-board grain: raster a 16-dot font with smoothing off,
//  one LED per font pixel. Glyphs come from the bundled jiskan16 subset.
//

import CoreGraphics
import CoreText
import Foundation
import UIKit

enum LEDQuantizer {
    static let kanjiSize = 16
    static let coverageThreshold: CGFloat = 0.5
    static let fontFileName = "Jiskan16s-Depart"
    static let fontPostScriptName = "Jiskan16sDepart-Regular"

    private static let registration = FontRegistration()

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

    static func glyph(for text: String) -> LEDMatrix.Glyph {
        registration.prepare()
        guard let raster = rasterize(text) else {
            return LEDMatrix.Glyph(width: kanjiSize, height: kanjiSize, rows: Array(repeating: 0, count: kanjiSize))
        }
        return quantize(
            coverage: raster.coverage,
            columns: raster.columns,
            rows: raster.rows,
            threshold: coverageThreshold
        )
    }

    private static func rasterize(_ text: String) -> (coverage: [CGFloat], columns: Int, rows: Int)? {
        let fontSize = CGFloat(kanjiSize)
        let ctFont = CTFontCreateWithName(fontPostScriptName as CFString, fontSize, nil)
        let loadedName = CTFontCopyPostScriptName(ctFont) as String
        guard loadedName == fontPostScriptName else { return nil }

        let chars = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        guard CTFontGetGlyphsForCharacters(ctFont, chars, &glyphs, chars.count) else { return nil }

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .default, &glyphs, &advance, 1)
        let columns = max(Int(advance.width.rounded()), 1)
        let rows = kanjiSize
        let count = columns * rows
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        bytes.initialize(repeating: 0, count: count)
        defer {
            bytes.deinitialize(count: count)
            bytes.deallocate()
        }

        guard let ctx = CGContext(
            data: bytes,
            width: columns,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: columns,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        ctx.setShouldAntialias(false)
        ctx.setAllowsAntialiasing(false)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldSubpixelPositionFonts(false)
        ctx.setShouldSubpixelQuantizeFonts(false)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
        ctx.setFillColor(gray: 1, alpha: 1)
        var position = CGPoint.zero
        CTFontDrawGlyphs(ctFont, glyphs, &position, 1, ctx)

        // Bitmap row 0 is the top of the image. Do not flip: a y-up draw
        // already puts the glyph head in the first rows.
        var coverage = [CGFloat](repeating: 0, count: count)
        for row in 0..<rows {
            for col in 0..<columns {
                coverage[row * columns + col] = CGFloat(bytes[row * columns + col]) / 255
            }
        }
        return (coverage, columns, rows)
    }
}

private final class FontRegistration {
    private var didRegister = false

    func prepare() {
        guard !didRegister else { return }
        didRegister = true
        let probe = CTFontCreateWithName(LEDQuantizer.fontPostScriptName as CFString, 16, nil)
        if (CTFontCopyPostScriptName(probe) as String) == LEDQuantizer.fontPostScriptName {
            return
        }
        guard let url = Self.fontURL() else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func fontURL() -> URL? {
        let bundles = [Bundle.main, Bundle(for: FontRegistration.self)]
        for bundle in bundles {
            if let urls = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) {
                if let match = urls.first(where: { $0.deletingPathExtension().lastPathComponent == LEDQuantizer.fontFileName }) {
                    return match
                }
            }
            if let url = bundle.url(forResource: LEDQuantizer.fontFileName, withExtension: "ttf") {
                return url
            }
        }
        return nil
    }
}
