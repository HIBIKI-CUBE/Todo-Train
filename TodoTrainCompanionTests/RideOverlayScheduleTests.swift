import AppKit
import Foundation
import SwiftUI
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

@MainActor
@Suite("Mac PiP schedule readout")
struct RideOverlayScheduleTests {
    @Test func scheduleStaysInsideTheCard() throws {
        let cases: [(String, RideOverlayPresentation)] = [
            ("none", rideSnap(title: "週次レポート")),
            ("short", rideSnap(title: "週次レポート", nextTitle: "定例", startsAt: 1_768_000_400)),
            (
                "long",
                rideSnap(
                    title: "週次レポートの準備を終えてからレビューに入る",
                    nextTitle: "四半期の振り返りと次のスプリントの計画を書く",
                    startsAt: 1_768_003_780
                )
            ),
            (
                "current",
                rideSnap(
                    title: "原稿",
                    nextTitle: "デザインレビュー",
                    startsAt: 1_768_000_000,
                    endsAt: 1_768_001_320
                )
            ),
        ]
        let scale: CGFloat = 2
        let card = RideOverlayGeometry.cardSize
        let pad: CGFloat = 24
        for (name, presentation) in cases {
            let renderer = ImageRenderer(content: ridePreviewCanvas(presentation))
            renderer.scale = scale
            renderer.isOpaque = true
            let image = try #require(renderer.nsImage)
            let rep = try #require(bitmap(image))
            #expect(rep.pixelsWide == Int((card.width + pad * 2) * scale))
            #expect(rep.pixelsHigh == Int((card.height + pad * 2) * scale))
            let spilled = spilledPixels(in: rep, scale: scale, pad: pad, card: card)
            #expect(spilled == 0, "\(name) painted \(spilled) px outside the PiP")
        }
    }

    private func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    /// Pixels clearly outside the rounded card. Antialiased edge pixels are ignored.
    private func spilledPixels(
        in rep: NSBitmapImageRep,
        scale: CGFloat,
        pad: CGFloat,
        card: OverlaySize
    ) -> Int {
        let rect = CGRect(x: pad, y: pad, width: card.width, height: card.height)
        let radius = RideOverlayGeometry.cornerRadius
        var spilled = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                guard roundedRectSDF(point, rect: rect, radius: radius) > 1.5 else { continue }
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if !isCanvas(color) { spilled += 1 }
            }
        }
        return spilled
    }

    private func isCanvas(_ color: NSColor) -> Bool {
        let gray = 0.32
        return abs(color.redComponent - gray) < 0.08
            && abs(color.greenComponent - gray) < 0.08
            && abs(color.blueComponent - gray) < 0.08
    }

    private func roundedRectSDF(_ point: CGPoint, rect: CGRect, radius: CGFloat) -> CGFloat {
        let half = CGSize(width: rect.width / 2, height: rect.height / 2)
        let local = CGPoint(x: point.x - rect.midX, y: point.y - rect.midY)
        let box = CGPoint(
            x: abs(local.x) - half.width + radius,
            y: abs(local.y) - half.height + radius
        )
        let outside = hypot(max(box.x, 0), max(box.y, 0))
        let inside = min(max(box.x, box.y), 0)
        return outside + inside - radius
    }
}
