//
//  TicketStampBundleLayout.swift
//  Todo train
//
//  束は扇。spread 0 は隅の小さい弧、1 は Hub と同じ券面の弧。
//  扇は回さず、指の下の 1 枚だけ軸から離す。
//

import CoreGraphics
import Foundation
import TodoTrainSync
import TodoTrainTicketUI

enum TicketStampBundleLayout {
    /// たたんだ帯。履歴も運行終了もこれを超えない。
    static let collapsedBandMax: CGFloat = 140
    /// 運行終了の盤の縦余白を含めても帯が 140 を超えないよう、券面の扇はここまで。
    static let collapsedFanMax: CGFloat = 112
    static let compactRadiusRatio: CGFloat = 0.48
    /// 開いた扇の半径。券面幅に対する倍率。
    static let expandedRadiusRatio: CGFloat = 3.6
    /// 1 枚あたりの角度の上限。
    static let maxExpandedStepDegrees: Double = 28
    /// たたんだ弧の総角。枚数が増えても帯の大きさはここまで。
    static let collapsedArcDegrees: Double = 6.4
    static let safeMargin: CGFloat = 12
    /// 手前の券面の下端と、下ボタンやタブバーの上端とのあいだ。
    static let bottomClearance: CGFloat = 8
    /// 支点は券面の下半分。右端から半径だけ外。
    static let pivotYRatio: CGFloat = 0.64
    static let compactStepDegrees: Double = 1.6
    static let compactScale: CGFloat = 0.42
    static let baseWidth: CGFloat = 300
    static let expandedHeightMaxRatio: CGFloat = 0.55
    static let liftDistanceRatio: CGFloat = 0.075
    static let liftSpringResponse: Double = 0.12
    static let liftSpringDamping: Double = 0.86

    static let cornerSealSideRatio: CGFloat = 0.38
    static let cornerSealCenterXRatio: CGFloat = 0.66
    static let cornerSealCenterYRatio: CGFloat = 0.23
    static let cornerSealRotationDegrees: Double = -8

    static let openSpringResponse: Double = 0.18
    static let openSpringDamping: Double = 0.82
    static let closeSpringResponse: Double = 0.16
    static let closeSpringDamping: Double = 0.9

    struct Screen: Equatable {
        var width: CGFloat
        var height: CGFloat
        var safeTop: CGFloat = 0
        var safeLeading: CGFloat = 0
        var safeTrailing: CGFloat = 0
        var safeBottom: CGFloat = 0
        /// タブバーとは別に、画面内の下ボタンが占める高さ。
        var bottomObstacle: CGFloat = 0
        var hubColumnWidth: CGFloat

        var safeRect: CGRect {
            let bottom = max(0, safeBottom) + max(0, bottomObstacle)
            return CGRect(
                x: safeLeading,
                y: safeTop,
                width: max(1, width - safeLeading - safeTrailing),
                height: max(1, height - safeTop - bottom)
            )
        }

        var usableHeight: CGFloat { safeRect.height }
    }

    struct Placement: Equatable {
        var ticket: CGSize
        var radius: CGFloat
        var pivot: CGPoint
        /// いまの spread での、1 枚あたりの角度。
        var step: Double
        /// 角度 0 の券面の左上。
        var frontOrigin: CGPoint
    }

    static func unit(_ spread: CGFloat) -> CGFloat {
        min(1, max(0, spread))
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        let u = unit(t)
        return a + (b - a) * u
    }

    static func lerp(_ a: Double, _ b: Double, _ t: CGFloat) -> Double {
        let u = Double(unit(t))
        return a + (b - a) * u
    }

    static func compactTicketSize() -> CGSize {
        let width = baseWidth * compactScale
        return CGSize(width: width, height: MarsTicketSpec.height(forWidth: width))
    }

    static func ticketSize(compact: CGSize, expanded: CGSize, spread: CGFloat) -> CGSize {
        CGSize(
            width: lerp(compact.width, expanded.width, spread),
            height: lerp(compact.height, expanded.height, spread)
        )
    }

    /// `spread` 0 は開いた券面に対する縮小、1 は等倍。
    static func visualScale(compact: CGSize, expanded: CGSize, spread: CGFloat) -> CGFloat {
        guard expanded.width > 1 else { return 1 }
        return ticketSize(compact: compact, expanded: expanded, spread: spread).width / expanded.width
    }

    /// Hub の切符の段。横で二段のときだけ、運行の段を除いた幅。
    static func hubColumnWidth(containerWidth: CGFloat, compactHeight: Bool) -> CGFloat {
        guard TrainLayout.shouldSplitHub(availableWidth: containerWidth, compactHeight: compactHeight) else {
            return max(1, containerWidth)
        }
        let pane = TrainLayout.hubServicePaneWidth(for: containerWidth)
        return max(1, containerWidth - pane)
    }

    /// Hub と同じ券面。高さが使える高さの 55% を超えるときだけ、その高さに縮める。
    static func expandedTicketSize(hubColumnWidth: CGFloat, usableHeight: CGFloat) -> CGSize {
        let natural = TrainLayout.ticketFaceSize(containerWidth: max(1, hubColumnWidth))
        let limit = max(1, usableHeight) * expandedHeightMaxRatio
        guard natural.height > limit else { return natural }
        let width = limit * MarsTicketSpec.aspectWidth / MarsTicketSpec.aspectHeight
        return CGSize(width: width, height: MarsTicketSpec.height(forWidth: width))
    }

    /// 右端から支点までの距離。両端を直線でつなぐ。
    static func radius(compactWidth: CGFloat, expandedWidth: CGFloat, spread: CGFloat) -> CGFloat {
        lerp(compactWidth * compactRadiusRatio, expandedWidth * expandedRadiusRatio, spread)
    }

    static func pivot(ticketWidth: CGFloat, ticketHeight: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: ticketWidth + radius, y: ticketHeight * pivotYRatio)
    }

    static func pivot(compact: CGSize, expanded: CGSize, spread: CGFloat) -> CGPoint {
        let size = ticketSize(compact: compact, expanded: expanded, spread: spread)
        let radius = radius(compactWidth: compact.width, expandedWidth: expanded.width, spread: spread)
        return pivot(ticketWidth: size.width, ticketHeight: size.height, radius: radius)
    }

    static func stepDegrees(spread: CGFloat, expandedStep: Double) -> Double {
        lerp(compactStepDegrees, expandedStep, spread)
    }

    /// 時計回りが正。奥の切符は左が持ち上がる。
    static func angleDegrees(depth: Double, spread: CGFloat, expandedStep: Double) -> Double {
        depth * stepDegrees(spread: spread, expandedStep: expandedStep)
    }

    /// 最新（index count−1）が 0。古いほど大きい。
    static func angle(index: Int, count: Int, step: Double) -> Double {
        guard count > 1 else { return 0 }
        return Double(max(0, count - 1 - index)) * step
    }

    /// 名前と角の印が見える角、枚あたりの上限、画面に収まる総角の、いちばん小さいもの。
    static func step(count: Int, clearStep: Double, arcBudget: Double) -> Double {
        guard count > 1 else { return 0 }
        let perCard = arcBudget / Double(count - 1)
        return min(clearStep, maxExpandedStepDegrees, perCard)
    }

    static func compactStep(count: Int) -> Double {
        let slots = Double(max(count - 1, 1))
        return min(compactStepDegrees, collapsedArcDegrees / slots)
    }

    /// focus 上の 1 枚が 1、隣が 0。
    static func lift(index: Int, focus: CGFloat) -> CGFloat {
        max(0, 1 - abs(CGFloat(index) - focus))
    }

    /// `lift` が 0.5 以上の 1 枚。同点は新しい側。
    static func liftsToFront(index: Int, focus: CGFloat, count: Int) -> Bool {
        let mine = lift(index: index, focus: focus)
        guard mine >= 0.5 else { return false }
        for other in 0..<count where other != index {
            let otherLift = lift(index: other, focus: focus)
            if otherLift > mine { return false }
            if otherLift == mine, other > index { return false }
        }
        return true
    }

    static func travelPerCard(viewportWidth: CGFloat, count: Int) -> CGFloat {
        let slots = CGFloat(max(count - 1, 1))
        let raw = max(0, viewportWidth) * TicketStampBundleGesture.dragWidthRatio / slots
        return min(
            TicketStampBundleGesture.maxTravelPerCard,
            max(TicketStampBundleGesture.minTravelPerCard, raw)
        )
    }

    /// 右（translation > 0）で focus が減る。0…count−1。
    static func focus(
        start: CGFloat,
        translation: CGFloat,
        travelPerCard: CGFloat,
        count: Int
    ) -> CGFloat {
        guard count > 0 else { return 0 }
        let span = max(travelPerCard, 0.001)
        let raw = start - translation / span
        return min(CGFloat(count - 1), max(0, raw))
    }

    static func rotate(_ point: CGPoint, around pivot: CGPoint, degrees: Double) -> CGPoint {
        let theta = degrees * .pi / 180
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        let c = cos(theta)
        let s = sin(theta)
        return CGPoint(
            x: pivot.x + c * dx - s * dy,
            y: pivot.y + s * dx + c * dy
        )
    }

    static func titleBottomLeft(ticketWidth: CGFloat) -> CGPoint {
        let scale = ticketWidth / baseWidth
        let x = MarsTicketSpec.contentPad * scale
        let y = (
            MarsTicketSpec.contentPad
                + MarsTicketSpec.durationTrackHeight
                + 6
                + MarsTicketSpec.titlePointSize
        ) * scale
        return CGPoint(x: x, y: y)
    }

    /// 角判の「定時」の下端。風景印を luxury 1 で置いた位置。
    static func onTimeTitleBottomCenter(ticketWidth: CGFloat, ticketHeight: CGFloat) -> CGPoint {
        let side = min(ticketWidth, ticketHeight) * cornerSealSideRatio
        let metrics = FukeiSealLayout.metrics(luxury: 1)
        let center = CGPoint(
            x: ticketWidth * cornerSealCenterXRatio,
            y: ticketHeight * cornerSealCenterYRatio
        )
        let localY = CGFloat(metrics.textBlockTop + metrics.titleSize) * side
        let unrotated = CGPoint(x: center.x, y: center.y - side / 2 + localY)
        return rotate(unrotated, around: center, degrees: cornerSealRotationDegrees)
    }

    static func placed(
        _ local: CGPoint,
        depth: Double,
        ticketWidth: CGFloat,
        ticketHeight: CGFloat,
        radius: CGFloat,
        spread: CGFloat,
        expandedStep: Double
    ) -> CGPoint {
        let pivot = pivot(ticketWidth: ticketWidth, ticketHeight: ticketHeight, radius: radius)
        let angle = angleDegrees(depth: depth, spread: spread, expandedStep: expandedStep)
        return rotate(local, around: pivot, degrees: angle)
    }

    /// 名前の下端と「定時」の下端が、手前の券面の上か左へ出ている。
    static func rearBandIsClear(
        ticketWidth: CGFloat,
        ticketHeight: CGFloat,
        step: Double,
        margin: CGFloat
    ) -> Bool {
        let radius = ticketWidth * expandedRadiusRatio
        let pivot = pivot(ticketWidth: ticketWidth, ticketHeight: ticketHeight, radius: radius)
        let name = rotate(titleBottomLeft(ticketWidth: ticketWidth), around: pivot, degrees: step)
        let mark = rotate(
            onTimeTitleBottomCenter(ticketWidth: ticketWidth, ticketHeight: ticketHeight),
            around: pivot,
            degrees: step
        )
        let front = CGRect(x: 0, y: 0, width: ticketWidth, height: ticketHeight)
        return isPeeking(name, front: front, margin: margin)
            && isPeeking(mark, front: front, margin: margin)
    }

    static func isPeeking(_ point: CGPoint, front: CGRect, margin: CGFloat) -> Bool {
        if point.y <= front.minY - margin { return true }
        if point.x <= front.minX - margin, point.y < front.midY { return true }
        return false
    }

    static func clearanceMargin(ticketHeight: CGFloat) -> CGFloat {
        max(8, ticketHeight * 0.035)
    }

    /// 開いたとき、1 枚奥の上の帯が見える最小角に少し足す。
    static func expandedStepDegrees(ticketWidth: CGFloat, ticketHeight: CGFloat) -> Double {
        let margin = clearanceMargin(ticketHeight: ticketHeight)
        let ceiling = 36.0
        guard rearBandIsClear(
            ticketWidth: ticketWidth,
            ticketHeight: ticketHeight,
            step: ceiling,
            margin: margin
        ) else {
            return ceiling
        }
        var low = compactStepDegrees
        var high = ceiling
        for _ in 0..<22 {
            let mid = (low + high) / 2
            if rearBandIsClear(
                ticketWidth: ticketWidth,
                ticketHeight: ticketHeight,
                step: mid,
                margin: margin
            ) {
                high = mid
            } else {
                low = mid
            }
        }
        return min(ceiling, high + 0.4)
    }

    static func placement(spread: CGFloat, count: Int, screen: Screen) -> Placement {
        let count = max(count, 1)
        let compact = compactTicketSize()
        let expanded = expandedTicketSize(
            hubColumnWidth: screen.hubColumnWidth,
            usableHeight: screen.usableHeight
        )
        let ticket = ticketSize(compact: compact, expanded: expanded, spread: spread)
        let radius = radius(compactWidth: compact.width, expandedWidth: expanded.width, spread: spread)
        let pivot = pivot(ticketWidth: ticket.width, ticketHeight: ticket.height, radius: radius)
        let openStep = expandedPerCardStep(count: count, ticket: expanded, screen: screen)
        let step = lerp(compactStep(count: count), openStep, spread)
        let folded = collapsedFrontOrigin(count: count, screen: screen)
        let opened = expandedFrontOrigin(ticket: expanded, screen: screen)
        return Placement(
            ticket: ticket,
            radius: radius,
            pivot: pivot,
            step: step,
            frontOrigin: CGPoint(
                x: lerp(folded.x, opened.x, spread),
                y: lerp(folded.y, opened.y, spread)
            )
        )
    }

    static func frontRect(_ placement: Placement) -> CGRect {
        CGRect(origin: placement.frontOrigin, size: placement.ticket)
    }

    static func markCenter(index: Int, count: Int, placement: Placement) -> CGPoint {
        let local = onTimeTitleBottomCenter(
            ticketWidth: placement.ticket.width,
            ticketHeight: placement.ticket.height
        )
        let angle = angle(index: index, count: count, step: placement.step)
        let rotated = rotate(local, around: placement.pivot, degrees: angle)
        return CGPoint(
            x: placement.frontOrigin.x + rotated.x,
            y: placement.frontOrigin.y + rotated.y
        )
    }

    /// 扇軸から離す量。引き出した券面が安全領域からはみ出す分は内側へ寄せ、`lift` で割る。
    static func liftOffset(
        index: Int,
        focus: CGFloat,
        count: Int,
        placement: Placement,
        safeRect: CGRect
    ) -> CGSize {
        let lift = lift(index: index, focus: focus)
        guard lift > 0.0001 else { return .zero }
        let angle = angle(index: index, count: count, step: placement.step)
        let distance = placement.ticket.width * liftDistanceRatio
        let radial = radialPull(angle: angle, distance: distance)
        let aabb = cardBounds(placement: placement, angle: angle, extra: radial)
        let contain = shiftInto(aabb, safe: safeRect)
        return CGSize(
            width: (radial.width + contain.width) * lift,
            height: (radial.height + contain.height) * lift
        )
    }

    static func stackBounds(count: Int, placement: Placement) -> CGRect {
        var rect = CGRect.null
        let corners = ticketCorners(placement.ticket)
        let count = max(count, 1)
        for index in 0..<count {
            let angle = angle(index: index, count: count, step: placement.step)
            for corner in corners {
                let rotated = rotate(corner, around: placement.pivot, degrees: angle)
                let point = CGPoint(
                    x: placement.frontOrigin.x + rotated.x,
                    y: placement.frontOrigin.y + rotated.y
                )
                rect = rect.union(CGRect(origin: point, size: .zero))
            }
        }
        if rect.isNull {
            return frontRect(placement)
        }
        return rect
    }

    /// 容器の下端から、下ボタン（またはタブバー）と余白を除いた扇の高さ。
    static func usableFanHeight(
        fittingHeight: CGFloat,
        bottomObstacle: CGFloat,
        bottomClearance: CGFloat
    ) -> CGFloat {
        fittingHeight - max(0, bottomObstacle) - max(0, bottomClearance)
    }

    /// 新しい切符ほど上。
    static func stackRank(index: Int) -> Double {
        Double(index)
    }

    static var collapsedFanSize: CGSize {
        let size = compactTicketSize()
        let radius = size.width * compactRadiusRatio
        let pivot = pivot(ticketWidth: size.width, ticketHeight: size.height, radius: radius)
        let bounds = localStackBounds(
            ticket: size,
            pivot: pivot,
            step: compactStepDegrees,
            count: 5
        )
        let width = max(bounds.maxX, size.width) - min(bounds.minX, 0)
        let height = max(bounds.maxY, size.height) - min(bounds.minY, 0)
        return CGSize(width: ceil(width), height: ceil(height))
    }

    static var collapsedFanHeight: CGFloat { collapsedFanSize.height }

    /// 角の印が安全領域に残り、名前の書き出しが上端より下に残る、いちばん大きい総角。
    static func arcBudget(count: Int, ticket: CGSize, screen: Screen) -> Double {
        let slots = Double(max(count - 1, 1))
        let ceiling = maxExpandedStepDegrees * slots
        let origin = expandedFrontOrigin(ticket: ticket, screen: screen)
        let radius = ticket.width * expandedRadiusRatio
        let pivot = pivot(ticketWidth: ticket.width, ticketHeight: ticket.height, radius: radius)
        func fits(_ total: Double) -> Bool {
            let step = slots > 0 ? total / slots : 0
            let placement = Placement(
                ticket: ticket,
                radius: radius,
                pivot: pivot,
                step: step,
                frontOrigin: origin
            )
            return bandStaysInSafeArea(count: max(count, 1), placement: placement, screen: screen)
        }
        guard fits(0) else { return 0 }
        if fits(ceiling) { return ceiling }
        var low = 0.0
        var high = ceiling
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if fits(mid) {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    private static func expandedPerCardStep(count: Int, ticket: CGSize, screen: Screen) -> Double {
        let clear = expandedStepDegrees(ticketWidth: ticket.width, ticketHeight: ticket.height)
        let budget = arcBudget(count: count, ticket: ticket, screen: screen)
        return step(count: count, clearStep: clear, arcBudget: budget)
    }

    private static func bandStaysInSafeArea(count: Int, placement: Placement, screen: Screen) -> Bool {
        let safe = screen.safeRect.insetBy(dx: 1, dy: 1)
        guard safe.width > 2, safe.height > 2 else { return false }
        for index in 0..<count {
            let mark = markCenter(index: index, count: count, placement: placement)
            if !safe.contains(mark) { return false }
            let title = titleOnScreen(index: index, count: count, placement: placement)
            if title.y < safe.minY { return false }
        }
        return true
    }

    private static func titleOnScreen(index: Int, count: Int, placement: Placement) -> CGPoint {
        let local = titleBottomLeft(ticketWidth: placement.ticket.width)
        let angle = angle(index: index, count: count, step: placement.step)
        let rotated = rotate(local, around: placement.pivot, degrees: angle)
        return CGPoint(
            x: placement.frontOrigin.x + rotated.x,
            y: placement.frontOrigin.y + rotated.y
        )
    }

    private static func collapsedFrontOrigin(count: Int, screen: Screen) -> CGPoint {
        let ticket = compactTicketSize()
        let radius = ticket.width * compactRadiusRatio
        let pivot = pivot(ticketWidth: ticket.width, ticketHeight: ticket.height, radius: radius)
        let step = compactStep(count: count)
        let bounds = localStackBounds(ticket: ticket, pivot: pivot, step: step, count: max(count, 1))
        let right = screen.width - max(screen.safeTrailing, safeMargin)
        let bottom = screen.height - screen.safeBottom - max(0, screen.bottomObstacle) - bottomClearance
        return CGPoint(x: right - bounds.maxX, y: bottom - bounds.maxY)
    }

    private static func expandedFrontOrigin(ticket: CGSize, screen: Screen) -> CGPoint {
        let columnX = screen.width - screen.hubColumnWidth
        var origin = CGPoint(
            x: columnX + (screen.hubColumnWidth - ticket.width) / 2,
            y: screen.safeRect.maxY - bottomClearance - ticket.height
        )
        let rect = CGRect(origin: origin, size: ticket)
        let shift = shiftInto(rect, safe: screen.safeRect)
        origin.x += shift.width
        origin.y += shift.height
        return origin
    }

    private static func localStackBounds(
        ticket: CGSize,
        pivot: CGPoint,
        step: Double,
        count: Int
    ) -> CGRect {
        var rect = CGRect.null
        let corners = ticketCorners(ticket)
        let count = max(count, 1)
        for depth in 0..<count {
            let angle = Double(depth) * step
            for corner in corners {
                let point = rotate(corner, around: pivot, degrees: angle)
                rect = rect.union(CGRect(origin: point, size: .zero))
            }
        }
        if rect.isNull {
            return CGRect(origin: .zero, size: ticket)
        }
        return rect
    }

    private static func ticketCorners(_ ticket: CGSize) -> [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: ticket.width, y: 0),
            CGPoint(x: 0, y: ticket.height),
            CGPoint(x: ticket.width, y: ticket.height),
        ]
    }

    private static func radialPull(angle: Double, distance: CGFloat) -> CGSize {
        let theta = angle * .pi / 180
        return CGSize(width: -CGFloat(cos(theta)) * distance, height: -CGFloat(sin(theta)) * distance)
    }

    private static func cardBounds(placement: Placement, angle: Double, extra: CGSize) -> CGRect {
        var rect = CGRect.null
        for corner in ticketCorners(placement.ticket) {
            let rotated = rotate(corner, around: placement.pivot, degrees: angle)
            let point = CGPoint(
                x: placement.frontOrigin.x + rotated.x + extra.width,
                y: placement.frontOrigin.y + rotated.y + extra.height
            )
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    private static func shiftInto(_ rect: CGRect, safe: CGRect) -> CGSize {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if rect.minX < safe.minX {
            dx += safe.minX - rect.minX
        }
        if rect.maxX + dx > safe.maxX {
            dx += safe.maxX - (rect.maxX + dx)
        }
        if rect.minY < safe.minY {
            dy += safe.minY - rect.minY
        }
        if rect.maxY + dy > safe.maxY {
            dy += safe.maxY - (rect.maxY + dy)
        }
        return CGSize(width: dx, height: dy)
    }
}
