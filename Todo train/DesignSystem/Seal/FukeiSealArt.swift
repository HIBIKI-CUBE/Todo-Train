//
//  FukeiSealArt.swift
//  Todo train
//
//  風景印の絵。季節 4、日と月 4、紋 4、線路。確率は入れない。
//

import SwiftUI
import TodoTrainSync

enum FukeiSealArt {
    struct Ink {
        var fill = Path()
        var stroke = Path()
        var evenOdd = false
    }

    static func scene(season: PunctualityJudgment.StampSeason, in rect: CGRect) -> Ink {
        var ink = Ink()
        let box = Box(rect: rect)
        switch season {
        case .spring:
            spring(box, into: &ink)
        case .summer:
            summer(box, into: &ink)
        case .autumn:
            autumn(box, into: &ink)
        case .winter:
            winter(box, into: &ink)
        }
        return ink
    }

    static func sky(timeOfDay: PunctualityJudgment.StampTimeOfDay, in rect: CGRect) -> Ink {
        var ink = Ink()
        let box = Box(rect: rect)
        switch timeOfDay {
        case .morning:
            ink.fill.addEllipse(in: box.circle(0.50, 0.70, 0.30))
        case .afternoon:
            ink.fill.addEllipse(in: box.circle(0.50, 0.36, 0.26))
        case .evening:
            let radius = box.span(0.32)
            let center = box.p(0.50, 0.64)
            upperSemicircle(center: center, radius: radius, into: &ink.fill)
            ink.stroke.move(to: box.p(0.08, 0.64))
            ink.stroke.addLine(to: box.p(0.92, 0.64))
        case .night:
            night(box, into: &ink)
        }
        return ink
    }

    static func rails(in rect: CGRect) -> Ink {
        var stroke = Path()
        let box = Box(rect: rect)
        stroke.move(to: box.p(0.04, 0.86))
        stroke.addLine(to: box.p(0.96, 0.86))
        stroke.move(to: box.p(0.04, 0.945))
        stroke.addLine(to: box.p(0.96, 0.945))
        var x: CGFloat = 0.10
        while x <= 0.90 {
            stroke.move(to: box.p(x, 0.835))
            stroke.addLine(to: box.p(x, 0.97))
            x += 0.16
        }
        return Ink(stroke: stroke)
    }

    static func seasonMark(season: PunctualityJudgment.StampSeason, in rect: CGRect) -> Ink {
        var ink = Ink()
        let box = Box(rect: rect)
        switch season {
        case .spring:
            curve([box.p(0.18, 0.72), box.p(0.42, 0.48), box.p(0.70, 0.36)], into: &ink.stroke)
            ink.stroke.move(to: box.p(0.42, 0.48))
            ink.stroke.addLine(to: box.p(0.58, 0.62))
            blossom(at: box.p(0.70, 0.36), radius: box.span(0.11), into: &ink.fill)
            blossom(at: box.p(0.46, 0.42), radius: box.span(0.08), into: &ink.fill)
        case .summer:
            wave(box, y: 0.40, amplitude: 0.10, into: &ink.stroke)
            wave(box, y: 0.62, amplitude: 0.10, into: &ink.stroke)
        case .autumn:
            maple(at: box.p(0.50, 0.46), radius: box.span(0.34), into: &ink.fill)
            ink.stroke.move(to: box.p(0.50, 0.70))
            ink.stroke.addLine(to: box.p(0.50, 0.86))
        case .winter:
            ink.stroke.move(to: box.p(0.16, 0.74))
            ink.stroke.addLine(to: box.p(0.40, 0.50))
            ink.stroke.addLine(to: box.p(0.62, 0.38))
            ink.stroke.move(to: box.p(0.40, 0.50))
            ink.stroke.addLine(to: box.p(0.66, 0.62))
            ink.fill.addEllipse(in: box.circle(0.40, 0.50, 0.07))
            ink.fill.addEllipse(in: box.circle(0.62, 0.38, 0.08))
            ink.fill.addEllipse(in: box.circle(0.66, 0.62, 0.06))
        }
        return ink
    }

    private static func spring(_ box: Box, into ink: inout Ink) {
        curve(
            [box.p(0.00, 0.74), box.p(0.18, 0.50), box.p(0.36, 0.66), box.p(0.50, 0.76)],
            into: &ink.stroke
        )
        curve(
            [box.p(0.30, 0.76), box.p(0.55, 0.42), box.p(0.78, 0.60), box.p(1.00, 0.48)],
            into: &ink.stroke
        )
        curve(
            [box.p(1.02, 0.68), box.p(0.78, 0.52), box.p(0.58, 0.40), box.p(0.42, 0.28)],
            into: &ink.stroke
        )
        ink.stroke.move(to: box.p(0.72, 0.50))
        ink.stroke.addLine(to: box.p(0.86, 0.36))
        blossom(at: box.p(0.42, 0.28), radius: box.span(0.045), into: &ink.fill)
        blossom(at: box.p(0.58, 0.40), radius: box.span(0.038), into: &ink.fill)
        blossom(at: box.p(0.86, 0.36), radius: box.span(0.042), into: &ink.fill)
        blossom(at: box.p(0.74, 0.56), radius: box.span(0.032), into: &ink.fill)
    }

    private static func summer(_ box: Box, into ink: inout Ink) {
        curve(
            [box.p(0.00, 0.76), box.p(0.28, 0.36), box.p(0.52, 0.58), box.p(0.78, 0.32), box.p(1.00, 0.70)],
            into: &ink.stroke
        )
        wave(box, y: 0.50, amplitude: 0.07, into: &ink.stroke)
        wave(box, y: 0.62, amplitude: 0.07, into: &ink.stroke)
        wave(box, y: 0.74, amplitude: 0.05, into: &ink.stroke)
    }

    private static func autumn(_ box: Box, into ink: inout Ink) {
        curve(
            [box.p(0.00, 0.76), box.p(0.22, 0.30), box.p(0.40, 0.62), box.p(0.68, 0.26), box.p(1.00, 0.72)],
            into: &ink.stroke
        )
        curve(
            [box.p(-0.02, 0.70), box.p(0.22, 0.52), box.p(0.40, 0.38)],
            into: &ink.stroke
        )
        ink.stroke.move(to: box.p(0.24, 0.50))
        ink.stroke.addLine(to: box.p(0.12, 0.40))
        maple(at: box.p(0.40, 0.36), radius: box.span(0.07), into: &ink.fill)
        maple(at: box.p(0.22, 0.50), radius: box.span(0.055), into: &ink.fill)
        maple(at: box.p(0.12, 0.38), radius: box.span(0.05), into: &ink.fill)
    }

    private static func winter(_ box: Box, into ink: inout Ink) {
        curve(
            [box.p(0.00, 0.76), box.p(0.34, 0.22), box.p(0.62, 0.58), box.p(1.00, 0.70)],
            into: &ink.stroke
        )
        ink.stroke.move(to: box.p(0.98, 0.72))
        ink.stroke.addLine(to: box.p(0.72, 0.56))
        ink.stroke.addLine(to: box.p(0.56, 0.42))
        ink.stroke.move(to: box.p(0.72, 0.56))
        ink.stroke.addLine(to: box.p(0.84, 0.42))
        ink.fill.addEllipse(in: box.circle(0.34, 0.24, 0.035))
        ink.fill.addEllipse(in: box.circle(0.56, 0.42, 0.032))
        ink.fill.addEllipse(in: box.circle(0.72, 0.56, 0.028))
        ink.fill.addEllipse(in: box.circle(0.84, 0.42, 0.03))
        ink.fill.addEllipse(in: box.circle(0.90, 0.66, 0.026))
    }

    private static func night(_ box: Box, into ink: inout Ink) {
        let radius = box.span(0.26)
        let center = box.p(0.40, 0.46)
        ink.fill.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let shift = radius * 0.5
        ink.fill.addEllipse(
            in: CGRect(
                x: center.x - radius + shift,
                y: center.y - radius - radius * 0.12,
                width: radius * 2,
                height: radius * 2
            )
        )
        ink.evenOdd = true
        diamond(at: box.p(0.74, 0.28), radius: box.span(0.07), into: &ink.fill)
        diamond(at: box.p(0.86, 0.52), radius: box.span(0.045), into: &ink.fill)
        diamond(at: box.p(0.68, 0.66), radius: box.span(0.04), into: &ink.fill)
    }

    private static func blossom(at center: CGPoint, radius: CGFloat, into path: inout Path) {
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let orbit = radius * 0.9
        let petal = radius * 0.55
        for (dx, dy) in [(orbit, CGFloat(0)), (-orbit, CGFloat(0)), (CGFloat(0), orbit), (CGFloat(0), -orbit)] {
            path.addEllipse(
                in: CGRect(
                    x: center.x + dx - petal,
                    y: center.y + dy - petal,
                    width: petal * 2,
                    height: petal * 2
                )
            )
        }
    }

    private static func maple(at center: CGPoint, radius: CGFloat, into path: inout Path) {
        let verts: [(CGFloat, CGFloat)] = [
            (0, -1),
            (0.26, -0.32),
            (0.92, -0.38),
            (0.36, 0.02),
            (0.70, 0.82),
            (0, 0.30),
            (-0.70, 0.82),
            (-0.36, 0.02),
            (-0.92, -0.38),
            (-0.26, -0.32),
        ]
        guard let first = verts.first else { return }
        path.move(to: CGPoint(x: center.x + first.0 * radius, y: center.y + first.1 * radius))
        for vert in verts.dropFirst() {
            path.addLine(to: CGPoint(x: center.x + vert.0 * radius, y: center.y + vert.1 * radius))
        }
        path.closeSubpath()
    }

    private static func diamond(at center: CGPoint, radius: CGFloat, into path: inout Path) {
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius * 0.55, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius * 0.55, y: center.y))
        path.closeSubpath()
    }

    /// 地平線より上の半円。y は下向き。
    private static func upperSemicircle(center: CGPoint, radius: CGFloat, into path: inout Path) {
        let steps = 10
        path.move(to: CGPoint(x: center.x - radius, y: center.y))
        for step in 1 ... steps {
            let angle = Double.pi * (1 - Double(step) / Double(steps))
            path.addLine(
                to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y - CGFloat(sin(angle)) * radius
                )
            )
        }
        path.closeSubpath()
    }

    private static func wave(_ box: Box, y: CGFloat, amplitude: CGFloat, into path: inout Path) {
        path.move(to: box.p(0.02, y))
        path.addQuadCurve(to: box.p(0.50, y), control: box.p(0.26, y - amplitude))
        path.addQuadCurve(to: box.p(0.98, y), control: box.p(0.74, y + amplitude))
    }

    private static func curve(_ points: [CGPoint], into path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: first)
        guard points.count > 1 else { return }
        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }
        for index in 1 ..< points.count - 1 {
            let next = points[index + 1]
            let mid = CGPoint(x: (points[index].x + next.x) / 2, y: (points[index].y + next.y) / 2)
            path.addQuadCurve(to: mid, control: points[index])
        }
        path.addLine(to: points[points.count - 1])
    }

    private struct Box {
        var rect: CGRect

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        func span(_ fraction: CGFloat) -> CGFloat {
            fraction * min(rect.width, rect.height)
        }

        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> CGRect {
            let center = p(x, y)
            let r = span(radius)
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        }
    }
}
