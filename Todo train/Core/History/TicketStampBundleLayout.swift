//
//  TicketStampBundleLayout.swift
//  Todo train
//
//  束は扇。spread 0 は支点が近く半径の小さいたたみ、1 は支点が遠く半径の大きい弧。
//

import CoreGraphics
import Foundation
import TodoTrainSync
import TodoTrainTicketUI

enum TicketStampBundleLayout {
    static let depthCap = 4
    /// たたんだ帯。履歴も運行終了もこれを超えない。
    static let collapsedBandMax: CGFloat = 140
    /// 運行終了の盤の縦余白を含めても帯が 140 を超えないよう、券面の扇はここまで。
    static let collapsedFanMax: CGFloat = 112
    static let compactRadiusRatio: CGFloat = 0.48
    static let expandedRadiusRatio: CGFloat = 1.35
    /// 支点は券面の下半分。右端から半径だけ外。
    static let pivotYRatio: CGFloat = 0.64
    static let compactStepDegrees: Double = 1.6
    static let compactScale: CGFloat = 0.42
    static let baseWidth: CGFloat = 300
    /// 指をこの幅だけ横に動かすと、弧の上で 1 枚分進む。
    static let dragTravel: CGFloat = 72

    static let cornerSealSideRatio: CGFloat = 0.38
    static let cornerSealCenterXRatio: CGFloat = 0.66
    static let cornerSealCenterYRatio: CGFloat = 0.23
    static let cornerSealRotationDegrees: Double = -8

    static let openSpringResponse: Double = 0.26
    static let closeSpringResponse: Double = 0.18

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

    /// 右へ引くと古い切符へ。見た目の奥行きは下がる。
    static func visualDepth(index: Int, focus: CGFloat, drag: CGFloat) -> Double {
        let fraction = Double(min(max(drag / dragTravel, -1), 1))
        return Double(focus - CGFloat(index)) - fraction
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

    static func fanBounds(
        ticketWidth: CGFloat,
        ticketHeight: CGFloat,
        spread: CGFloat,
        expandedStep: Double,
        depthCap: Int = depthCap
    ) -> CGRect {
        let radius = ticketWidth * lerp(compactRadiusRatio, expandedRadiusRatio, spread)
        var rect = CGRect.null
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: ticketWidth, y: 0),
            CGPoint(x: 0, y: ticketHeight),
            CGPoint(x: ticketWidth, y: ticketHeight),
        ]
        for depth in 0...max(0, depthCap) {
            for corner in corners {
                let placed = placed(
                    corner,
                    depth: Double(depth),
                    ticketWidth: ticketWidth,
                    ticketHeight: ticketHeight,
                    radius: radius,
                    spread: spread,
                    expandedStep: expandedStep
                )
                rect = rect.union(CGRect(origin: placed, size: .zero))
            }
        }
        return rect.isNull ? CGRect(x: 0, y: 0, width: ticketWidth, height: ticketHeight) : rect
    }

    static var collapsedFanHeight: CGFloat {
        let size = compactTicketSize()
        let bounds = fanBounds(
            ticketWidth: size.width,
            ticketHeight: size.height,
            spread: 0,
            expandedStep: compactStepDegrees
        )
        let height = max(bounds.maxY, size.height) - min(bounds.minY, 0)
        return ceil(height)
    }

    /// 券面の右下を容器の右下に置いたとき、扇が容器の中に残る移動量。
    static func placementOffset(
        ticketWidth: CGFloat,
        ticketHeight: CGFloat,
        spread: CGFloat,
        expandedStep: Double,
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> CGSize {
        let bounds = fanBounds(
            ticketWidth: ticketWidth,
            ticketHeight: ticketHeight,
            spread: spread,
            expandedStep: expandedStep
        )
        let right = max(0, bounds.maxX - ticketWidth)
        let left = max(0, -bounds.minX)
        let down = max(0, bounds.maxY - ticketHeight)
        let roomX = max(0, containerWidth - ticketWidth)
        let shiftX = min(right, max(0, roomX - left))
        let roomY = max(0, containerHeight - ticketHeight)
        let shiftY = min(down, roomY)
        return CGSize(width: -shiftX, height: -shiftY)
    }

    /// 開いた扇が幅と高さに収まる券面。二分探索。
    static func expandedTicketSize(fittingWidth: CGFloat, fittingHeight: CGFloat) -> CGSize {
        guard fittingWidth > 48, fittingHeight > 48 else {
            let width: CGFloat = 120
            return CGSize(width: width, height: MarsTicketSpec.height(forWidth: width))
        }
        var low: CGFloat = 72
        var high = min(max(fittingWidth, low), 340)
        func fits(_ width: CGFloat) -> Bool {
            let height = MarsTicketSpec.height(forWidth: width)
            let step = expandedStepDegrees(ticketWidth: width, ticketHeight: height)
            let bounds = fanBounds(
                ticketWidth: width,
                ticketHeight: height,
                spread: 1,
                expandedStep: step
            )
            let usedWidth = max(bounds.maxX, width) - min(bounds.minX, 0)
            let usedHeight = max(bounds.maxY, height) - min(bounds.minY, 0)
            return usedWidth <= fittingWidth && usedHeight <= fittingHeight
        }
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if fits(mid) {
                low = mid
            } else {
                high = mid
            }
        }
        return CGSize(width: low, height: MarsTicketSpec.height(forWidth: low))
    }
}
