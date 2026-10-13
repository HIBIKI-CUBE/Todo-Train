//
//  CockpitSafeChrome.swift
//
//  Every Live Activity surface places content through this type.
//  It owns the clip (expanded island, compact pill, minimal circle,
//  lock screen / StandBy / Smart Stack card), the TrueDepth housing,
//  and the inset that keeps an axis-aligned slot inside that clip.
//  Inner corners are the outer radius minus that inset.
//  Callers do not add outer padding or their own corner radius.
//

import SwiftUI
import WidgetKit

enum CockpitSafeSlot: Equatable, Sendable {
    case all
    case leading
    case trailing
    case bottom
}

enum CockpitSafeSurface: Equatable, Sendable {
    /// Expanded Dynamic Island. Content wraps the TrueDepth housing.
    case islandExpanded
    /// One compact pill (leading or trailing). Both ends are caps.
    case islandCompact
    /// Minimal Dynamic Island. The clip is a circle.
    case islandMinimal
    /// Lock Screen card. StandBy is the same card in proposal points.
    case lockScreen
    case standBy
    /// Watch Smart Stack, and the narrow card used for `.small` / short `.medium`.
    case stack

    var wrapsCamera: Bool { self == .islandExpanded }

    static func fitting(width: CGFloat, height: CGFloat, fullscreen: Bool) -> CockpitSafeSurface {
        if fullscreen { return .standBy }
        if width >= 300 { return .lockScreen }
        return .stack
    }
}

/// Clip, camera housing, and the slots that stay inside both.
struct CockpitSafeChrome: Equatable, Sendable {
    /// Expanded island corner beside the camera. HIG's 44pt; the top row sits here.
    static let expandedOuterRadius: CGFloat = 44
    /// Expanded island bottom corner. Measured on a Pro Max expanded island:
    /// the bottom chord matches a 50pt corner, rounder than the 44pt top.
    /// The bottom slot's width is the chord of this radius, not a second padding guess.
    static let expandedBottomRadius: CGFloat = 50
    /// Lock Screen / StandBy card corner in proposal points.
    static let lockScreenOuterRadius: CGFloat = 24
    /// Smart Stack card corner.
    static let stackOuterRadius: CGFloat = 20
    /// Collapsed TrueDepth housing, centered on the expanded island's top edge.
    static let cameraHousing = CGSize(width: 126, height: 36.67)
    /// Space between the housing and a slot.
    static let cameraGap: CGFloat = 6
    /// Stop / resume tap target. Slots that hold it are at least this tall.
    static let controlSide: CGFloat = 44
    /// Gap under the top band before the gauge row.
    static let bandGap: CGFloat = 4

    var surface: CockpitSafeSurface
    var canvas: CGSize
    var clip: CockpitSafeClip
    var edgeInset: CGFloat
    var camera: CGRect?
    /// Single safe rect for surfaces that are not split by the camera.
    var content: CGRect
    var leading: CGRect
    var trailing: CGRect
    var bottom: CGRect

    var concentricRadius: CGFloat {
        max(0, clip.radius - edgeInset)
    }

    var guardedRects: [CGRect] {
        let rects = surface.wrapsCamera ? [leading, trailing, bottom] : [content]
        return rects.filter { $0.width > 0.5 && $0.height > 0.5 }
    }

    static var expandedEdgeInset: CGFloat { cornerInset(radius: expandedOuterRadius) }
    /// Horizontal inset of the bottom slot: the chord at the bottom clearance, both ends.
    static var expandedBottomChordInset: CGFloat {
        chordInset(radius: expandedBottomRadius, distanceFromEdge: expandedEdgeInset).rounded(.up)
    }
    static var lockScreenEdgeInset: CGFloat { cornerInset(radius: lockScreenOuterRadius) }
    static var stackEdgeInset: CGFloat { cornerInset(radius: stackOuterRadius) }
    static var compactEdgeInset: CGFloat {
        cornerInset(radius: CockpitSizeContract.islandCompactSide.height / 2)
    }
    static var minimalEdgeInset: CGFloat {
        cornerInset(radius: CockpitSizeContract.islandMinimalMaxWidth / 2)
    }

    /// Smallest inset whose rectangle stays inside a rounded rect of `radius`.
    /// A corner point at (inset, inset) lies on or inside the corner circle when
    /// inset ≥ radius × (1 − 1/√2). The value is rounded up so it clears the arc.
    static func cornerInset(radius: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        let raw = radius * (1 - 1 / CGFloat(2).squareRoot())
        return raw.rounded(.up)
    }

    /// How far a horizontal chord sits in from the straight side, `distanceFromEdge`
    /// up from the bottom (or down from the top) of a circular corner of `radius`.
    /// At the corner point this matches `cornerInset`. Closer to the edge the chord is narrower.
    static func chordInset(radius: CGFloat, distanceFromEdge: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        if distanceFromEdge >= radius { return 0 }
        if distanceFromEdge <= 0 { return radius }
        let dy = radius - distanceFromEdge
        let under = radius * radius - dy * dy
        guard under > 0 else { return radius }
        return radius - under.squareRoot()
    }

    static func resolve(surface: CockpitSafeSurface, canvas: CGSize) -> CockpitSafeChrome {
        let width = max(0, canvas.width)
        let height = max(0, canvas.height)
        let size = CGSize(width: width, height: height)
        let chrome: CockpitSafeChrome
        switch surface {
        case .islandExpanded:
            chrome = expanded(canvas: size)
        case .islandCompact:
            chrome = uniform(
                surface: surface,
                canvas: size,
                clip: .pill(radius: min(width, height) / 2),
                inset: cornerInset(radius: min(width, height) / 2)
            )
        case .islandMinimal:
            chrome = uniform(
                surface: surface,
                canvas: size,
                clip: .circle(radius: min(width, height) / 2),
                inset: cornerInset(radius: min(width, height) / 2)
            )
        case .lockScreen, .standBy:
            chrome = uniform(
                surface: surface,
                canvas: size,
                clip: .roundedRect(radius: lockScreenOuterRadius),
                inset: lockScreenEdgeInset
            )
        case .stack:
            chrome = uniform(
                surface: surface,
                canvas: size,
                clip: .roundedRect(radius: stackOuterRadius),
                inset: stackEdgeInset
            )
        }
        #if DEBUG
        if width >= 36, height >= 36 {
            for rect in chrome.guardedRects {
                assert(
                    chrome.contains(rect) && chrome.clearOfCamera(rect),
                    "CockpitSafeChrome slot left the safe region"
                )
            }
        }
        #endif
        return chrome
    }

    func contains(_ rect: CGRect) -> Bool {
        guard rect.width >= 0, rect.height >= 0 else { return false }
        if rect.isNull || rect.isEmpty { return true }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        return corners.allSatisfy(pointInsideClip)
    }

    func clearOfCamera(_ rect: CGRect) -> Bool {
        guard let camera, !rect.isEmpty else { return true }
        let gap = Self.cameraGap - 0.5
        let kept = camera.insetBy(dx: -gap, dy: -gap)
        return !kept.intersects(rect)
    }

    func pointInsideClip(_ point: CGPoint) -> Bool {
        let width = canvas.width
        let height = canvas.height
        guard point.x >= -0.01, point.y >= -0.01, point.x <= width + 0.01, point.y <= height + 0.01 else {
            return false
        }
        switch clip {
        case .circle:
            let radius = min(width, height) / 2
            let dx = point.x - width / 2
            let dy = point.y - height / 2
            return dx * dx + dy * dy <= radius * radius + 0.5
        case .pill, .roundedRect:
            return pointInsideRoundedRect(point, radius: clip.radius)
        case .uneven(let top, let bottom):
            return pointInsideUneven(point, top: top, bottom: bottom)
        }
    }

    func clipPath(in rect: CGRect) -> Path {
        switch clip {
        case .circle:
            return Circle().path(in: rect)
        case .pill:
            return Capsule().path(in: rect)
        case .roundedRect(let radius):
            return RoundedRectangle(cornerRadius: min(radius, min(rect.width, rect.height) / 2), style: .continuous)
                .path(in: rect)
        case .uneven(let top, let bottom):
            let limit = min(rect.width, rect.height) / 2
            return UnevenRoundedRectangle(
                topLeadingRadius: min(top, limit),
                bottomLeadingRadius: min(bottom, limit),
                bottomTrailingRadius: min(bottom, limit),
                topTrailingRadius: min(top, limit),
                style: .continuous
            )
            .path(in: rect)
        }
    }

    private func pointInsideRoundedRect(_ point: CGPoint, radius: CGFloat) -> Bool {
        let width = canvas.width
        let height = canvas.height
        let curve = min(max(radius, 0), min(width, height) / 2)
        if point.x < -0.01 || point.y < -0.01 || point.x > width + 0.01 || point.y > height + 0.01 {
            return false
        }
        let inCornerX = point.x < curve || point.x > width - curve
        let inCornerY = point.y < curve || point.y > height - curve
        if !(inCornerX && inCornerY) { return true }
        let centerX = point.x < curve ? curve : width - curve
        let centerY = point.y < curve ? curve : height - curve
        let dx = point.x - centerX
        let dy = point.y - centerY
        return dx * dx + dy * dy <= curve * curve + 0.5
    }

    /// Top and bottom corners can differ. A short island's bottom arc reaches past mid-height,
    /// so the corner is chosen by which edge the point is near, not by a half split.
    private func pointInsideUneven(_ point: CGPoint, top: CGFloat, bottom: CGFloat) -> Bool {
        let width = canvas.width
        let height = canvas.height
        if point.x < -0.01 || point.y < -0.01 || point.x > width + 0.01 || point.y > height + 0.01 {
            return false
        }
        let topRadius = min(max(top, 0), min(width, height) / 2)
        let bottomRadius = min(max(bottom, 0), min(width, height) / 2)
        let nearTop = point.y <= topRadius
        let nearBottom = point.y >= height - bottomRadius
        let radius: CGFloat
        let centerY: CGFloat
        if nearTop && nearBottom {
            if point.y <= height / 2 {
                radius = topRadius
                centerY = topRadius
            } else {
                radius = bottomRadius
                centerY = height - bottomRadius
            }
        } else if nearTop {
            radius = topRadius
            centerY = topRadius
        } else if nearBottom {
            radius = bottomRadius
            centerY = height - bottomRadius
        } else {
            return true
        }
        let nearSide = point.x <= radius || point.x >= width - radius
        if !nearSide { return true }
        let centerX = point.x <= radius ? radius : width - radius
        let dx = point.x - centerX
        let dy = point.y - centerY
        return dx * dx + dy * dy <= radius * radius + 0.5
    }

    private static func expanded(canvas: CGSize) -> CockpitSafeChrome {
        let inset = expandedEdgeInset
        let width = canvas.width
        let height = canvas.height
        let budget = width - 2 * cameraGap - 2 * controlSide - 2 * inset
        let cameraWidth = min(cameraHousing.width, max(0, budget))
        let cameraHeight = min(cameraHousing.height, max(0, height - inset))
        let camera = CGRect(
            x: (width - cameraWidth) / 2,
            y: 0,
            width: cameraWidth,
            height: cameraHeight
        )
        let top = inset
        // The action row is reserved under the camera before the top band takes space,
        // so a short island cannot push 再乗車 out. Extra height stays in the bottom slot.
        let bottomReserve = controlSide
        let scheduleBand = CockpitFaceMetrics.expanded.scheduleBand
        let slotBottom = height - inset
        let bottomFloor = camera.maxY + bandGap
        let bottomLimit = max(bottomFloor, slotBottom - bottomReserve)
        let naturalTop = max(controlSide, scheduleBand, camera.maxY - top)
        let topLimit = max(0, bottomLimit - bandGap - top)
        let sideHeight = min(naturalTop, topLimit)
        let leading = CGRect(
            x: inset,
            y: top,
            width: max(0, camera.minX - cameraGap - inset),
            height: max(0, sideHeight)
        )
        let trailingX = camera.maxX + cameraGap
        let trailing = CGRect(
            x: trailingX,
            y: top,
            width: max(0, width - inset - trailingX),
            height: max(0, sideHeight)
        )
        let bottomY = min(max(bottomFloor, top + sideHeight + bandGap), slotBottom)
        // Chord at the slot's bottom edge. Both ends move in by the same amount.
        let horizontal = chordInset(
            radius: expandedBottomRadius,
            distanceFromEdge: max(0, height - slotBottom)
        ).rounded(.up)
        let bottom = CGRect(
            x: horizontal,
            y: bottomY,
            width: max(0, width - 2 * horizontal),
            height: max(0, slotBottom - bottomY)
        )
        return CockpitSafeChrome(
            surface: .islandExpanded,
            canvas: canvas,
            clip: .uneven(top: expandedOuterRadius, bottom: expandedBottomRadius),
            edgeInset: inset,
            camera: camera,
            content: .null,
            leading: leading,
            trailing: trailing,
            bottom: bottom
        )
    }

    private static func uniform(
        surface: CockpitSafeSurface,
        canvas: CGSize,
        clip: CockpitSafeClip,
        inset: CGFloat
    ) -> CockpitSafeChrome {
        let content = CGRect(
            x: inset,
            y: inset,
            width: max(0, canvas.width - 2 * inset),
            height: max(0, canvas.height - 2 * inset)
        )
        return CockpitSafeChrome(
            surface: surface,
            canvas: canvas,
            clip: clip,
            edgeInset: inset,
            camera: nil,
            content: content,
            leading: .zero,
            trailing: .zero,
            bottom: .zero
        )
    }
}

enum CockpitSafeClip: Equatable, Sendable {
    case roundedRect(radius: CGFloat)
    /// Expanded island. The bottom corners are rounder than the top.
    case uneven(top: CGFloat, bottom: CGFloat)
    case pill(radius: CGFloat)
    case circle(radius: CGFloat)

    var radius: CGFloat {
        switch self {
        case .roundedRect(let radius), .pill(let radius), .circle(let radius):
            return radius
        case .uneven(let top, _):
            return top
        }
    }
}

// MARK: - Placement

private struct CockpitConcentricRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = CockpitSafeChrome.expandedOuterRadius - CockpitSafeChrome.expandedEdgeInset
}

extension EnvironmentValues {
    /// Outer clip radius minus the safe inset. Buttons read this instead of picking a radius.
    var cockpitConcentricRadius: CGFloat {
        get { self[CockpitConcentricRadiusKey.self] }
        set { self[CockpitConcentricRadiusKey.self] = newValue }
    }
}

struct CockpitConcentricCorner: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let curve = min(max(radius, 0), limit)
        return RoundedRectangle(cornerRadius: curve, style: .continuous).path(in: rect)
    }
}

/// Full-canvas placement. Expanded splits around the camera. Other surfaces
/// put one face in the single safe rect. No outer padding.
struct CockpitSafeHost<Face: View, Leading: View, Trailing: View, Bottom: View>: View {
    var surface: CockpitSafeSurface
    @ViewBuilder var face: () -> Face
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        GeometryReader { geo in
            let chrome = CockpitSafeChrome.resolve(surface: surface, canvas: geo.size)
            Group {
                if surface.wrapsCamera {
                    ZStack(alignment: .topLeading) {
                        leading()
                            .frame(width: chrome.leading.width, height: chrome.leading.height, alignment: .topLeading)
                            .offset(x: chrome.leading.minX, y: chrome.leading.minY)
                        trailing()
                            .frame(width: chrome.trailing.width, height: chrome.trailing.height, alignment: .topTrailing)
                            .offset(x: chrome.trailing.minX, y: chrome.trailing.minY)
                        bottom()
                            .frame(width: chrome.bottom.width, height: chrome.bottom.height, alignment: .topLeading)
                            .offset(x: chrome.bottom.minX, y: chrome.bottom.minY)
                    }
                } else {
                    face()
                        .frame(width: chrome.content.width, height: chrome.content.height, alignment: .topLeading)
                        .offset(x: chrome.content.minX, y: chrome.content.minY)
                }
            }
            .environment(\.cockpitConcentricRadius, chrome.concentricRadius)
        }
    }
}

/// One safe rect. Compact and minimal previews use this. The live pills use
/// `contentMargins` with the same inset, so the widget views do not also inset.
struct CockpitSafeInset<Content: View>: View {
    var surface: CockpitSafeSurface
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let chrome = CockpitSafeChrome.resolve(surface: surface, canvas: geo.size)
            content()
                .frame(width: chrome.content.width, height: chrome.content.height)
                .offset(x: chrome.content.minX, y: chrome.content.minY)
        }
    }
}

struct CockpitSafeClipShape: Shape {
    var surface: CockpitSafeSurface

    func path(in rect: CGRect) -> Path {
        CockpitSafeChrome.resolve(surface: surface, canvas: rect.size).clipPath(in: rect)
    }
}

/// Documentation stroke of the system clip and, on the expanded island, the camera pill.
struct CockpitSafeClipOverlay: View {
    var surface: CockpitSafeSurface

    var body: some View {
        GeometryReader { geo in
            let chrome = CockpitSafeChrome.resolve(surface: surface, canvas: geo.size)
            ZStack {
                chrome.clipPath(in: CGRect(origin: .zero, size: geo.size))
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
                if let camera = chrome.camera {
                    Capsule()
                        .fill(Color.black)
                        .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
                        .frame(width: camera.width, height: camera.height)
                        .position(x: camera.midX, y: camera.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

extension DynamicIslandExpandedRegion {
    func safeLeadingChrome() -> DynamicIslandExpandedRegion<Content> {
        contentMargins(.top, CockpitSafeChrome.expandedEdgeInset)
            .contentMargins(.leading, CockpitSafeChrome.expandedEdgeInset)
    }

    func safeTrailingChrome() -> DynamicIslandExpandedRegion<Content> {
        contentMargins(.top, CockpitSafeChrome.expandedEdgeInset)
            .contentMargins(.trailing, CockpitSafeChrome.expandedEdgeInset)
    }

    func safeBottomChrome() -> DynamicIslandExpandedRegion<Content> {
        contentMargins(.horizontal, CockpitSafeChrome.expandedBottomChordInset)
            .contentMargins(.bottom, CockpitSafeChrome.expandedEdgeInset)
    }
}

extension DynamicIsland {
    func safeCompactChrome() -> DynamicIsland {
        contentMargins(.all, CockpitSafeChrome.compactEdgeInset, for: .compactLeading)
            .contentMargins(.all, CockpitSafeChrome.compactEdgeInset, for: .compactTrailing)
            .contentMargins(.all, CockpitSafeChrome.minimalEdgeInset, for: .minimal)
    }
}
