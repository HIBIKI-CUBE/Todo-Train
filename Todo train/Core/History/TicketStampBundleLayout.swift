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
    /// 開いた扇の半径の上限。弧をゆるくして、奥の切符が右へ大きく出ないようにする。
    /// 矩形に収まらないときはこれより小さくする。
    static let expandedRadiusRatio: CGFloat = 3.6
    /// 1 枚あたりの角度の上限。矩形に収まらないときはこれより小さくする。
    static let maxExpandedStepDegrees: Double = 28
    /// 手前の券面の右下を、容器の右下からこれより内側へ寄せない。
    static let maxCornerInset: CGFloat = 64
    static let safeMargin: CGFloat = 12
    /// 手前の券面の下端と、下ボタンやタブバーの上端とのあいだ。
    static let bottomClearance: CGFloat = 8
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
        radius: CGFloat,
        spread: CGFloat,
        expandedStep: Double,
        depthCap: Int = depthCap
    ) -> CGRect {
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

    /// 新しい切符ほど上。開閉の途中でも、めくりで focus が動いても順は変えない。
    static func stackRank(index: Int) -> Double {
        Double(index)
    }

    static var collapsedFanSize: CGSize {
        let size = compactTicketSize()
        let bounds = fanBounds(
            ticketWidth: size.width,
            ticketHeight: size.height,
            radius: size.width * compactRadiusRatio,
            spread: 0,
            expandedStep: compactStepDegrees
        )
        let width = max(bounds.maxX, size.width) - min(bounds.minX, 0)
        let height = max(bounds.maxY, size.height) - min(bounds.minY, 0)
        return CGSize(width: ceil(width), height: ceil(height))
    }

    static var collapsedFanHeight: CGFloat { collapsedFanSize.height }

    struct ExpandedFan: Equatable {
        var ticket: CGSize
        var radius: CGFloat
        var stepDegrees: Double
        /// 開いた扇で、手前の券面の右下より外接が右や下へ出る量。収める計算に使う。
        var cornerInset: CGSize
    }

    /// 容器の下端から、下ボタン（またはタブバー）と余白を除いた扇の高さ。
    static func usableFanHeight(
        fittingHeight: CGFloat,
        bottomObstacle: CGFloat,
        bottomClearance: CGFloat
    ) -> CGFloat {
        fittingHeight - max(0, bottomObstacle) - max(0, bottomClearance)
    }

    /// 開いた扇が矩形に収まる券面・半径・角度。
    /// 手前の券面の右下は `cornerInset` だけ内側に固定し、奥の切符が右や下へ出た分も矩形の中に置く。
    /// 矩形の下端には `bottomObstacle`（下ボタンやタブバー）と `bottomClearance` を含める。扇の下端はその上で止める。
    /// 半径は券面幅の `expandedRadiusRatio` 倍まで、角度は名前と角判が見える角と `maxExpandedStepDegrees` までのうち小さい方。
    /// 矩形が狭いときは、その上限より開きを小さくして収める。
    static func expandedFan(
        fittingWidth: CGFloat,
        fittingHeight: CGFloat,
        depth: Int,
        bottomObstacle: CGFloat = 0,
        bottomClearance: CGFloat = 0
    ) -> ExpandedFan {
        let depth = max(0, depth)
        let fittingHeight = usableFanHeight(
            fittingHeight: fittingHeight,
            bottomObstacle: bottomObstacle,
            bottomClearance: bottomClearance
        )
        guard fittingWidth > 72, fittingHeight > 72 else {
            let width = min(96, max(48, fittingWidth - 8))
            return makeFan(width: width, scale: 0, depth: depth)
        }

        func solve(limitInset: Bool) -> (scale: CGFloat, width: CGFloat)? {
            func fits(width: CGFloat, scale: CGFloat) -> Bool {
                let height = MarsTicketSpec.height(forWidth: width)
                guard width <= fittingWidth, height <= fittingHeight else { return false }
                let fan = makeFan(width: width, scale: scale, depth: depth)
                if limitInset,
                   fan.cornerInset.width > maxCornerInset || fan.cornerInset.height > maxCornerInset {
                    return false
                }
                let rect = expandedFanRect(
                    fan: fan,
                    fittingWidth: fittingWidth,
                    fittingHeight: fittingHeight,
                    depth: depth
                )
                return rect.minX >= -0.5
                    && rect.minY >= -0.5
                    && rect.maxX <= fittingWidth + 0.5
                    && rect.maxY <= fittingHeight + 0.5
            }

            func widest(at scale: CGFloat) -> CGFloat? {
                let floor: CGFloat = 48
                guard fits(width: floor, scale: scale) else { return nil }
                var low = floor
                var high = min(max(fittingWidth - safeMargin, floor), 320)
                for _ in 0..<16 {
                    let mid = (low + high) / 2
                    if fits(width: mid, scale: scale) {
                        low = mid
                    } else {
                        high = mid
                    }
                }
                return low
            }

            guard let folded = widest(at: 0) else { return nil }
            if let full = widest(at: 1) {
                return (1, full)
            }
            var bestScale: CGFloat = 0
            var bestWidth = folded
            var low: CGFloat = 0
            var high: CGFloat = 1
            for _ in 0..<16 {
                let mid = (low + high) / 2
                if let width = widest(at: mid) {
                    bestScale = mid
                    bestWidth = width
                    low = mid
                } else {
                    high = mid
                }
            }
            return (bestScale, bestWidth)
        }

        if let solved = solve(limitInset: true) ?? solve(limitInset: false) {
            return makeFan(width: solved.width, scale: solved.scale, depth: depth)
        }
        return makeFan(width: 64, scale: 0, depth: depth)
    }

    /// 開いた扇を、下の障害物の上で右下に外接が接するように置いた範囲。
    static func expandedFanRect(
        fan: ExpandedFan,
        fittingWidth: CGFloat,
        fittingHeight: CGFloat,
        depth: Int,
        bottomObstacle: CGFloat = 0,
        bottomClearance: CGFloat = 0
    ) -> CGRect {
        let bounds = fanBounds(
            ticketWidth: fan.ticket.width,
            ticketHeight: fan.ticket.height,
            radius: fan.radius,
            spread: 1,
            expandedStep: fan.stepDegrees,
            depthCap: max(0, depth)
        )
        let usableHeight = usableFanHeight(
            fittingHeight: fittingHeight,
            bottomObstacle: bottomObstacle,
            bottomClearance: bottomClearance
        )
        return bounds.offsetBy(
            dx: fittingWidth - fan.ticket.width - fan.cornerInset.width,
            dy: usableHeight - fan.ticket.height - fan.cornerInset.height
        )
    }

    /// 手前の券面の左上を容器に置いた位置。
    /// x は spread 0（外接の右端が右余白）と spread 1（外接の水平中心が容器の中央）の直線補間。
    /// 中央に置くと安全領域からはみ出すときは、収まる側へ寄せる。
    /// y は、その spread の外接の下端が使える高さの下端に来るようにする。
    static func fanOrigin(
        fan: ExpandedFan,
        spread: CGFloat,
        fittingWidth: CGFloat,
        fittingHeight: CGFloat,
        depth: Int,
        bottomObstacle: CGFloat = 0,
        bottomClearance: CGFloat = 0
    ) -> CGPoint {
        let spread = unit(spread)
        let usableHeight = usableFanHeight(
            fittingHeight: fittingHeight,
            bottomObstacle: bottomObstacle,
            bottomClearance: bottomClearance
        )
        let bounds = geometry(fan: fan, spread: spread, depth: depth).bounds
        let leading = collapsedOriginX(fan: fan, fittingWidth: fittingWidth, depth: depth)
        let centered = centeredOriginX(fan: fan, fittingWidth: fittingWidth, depth: depth)
        return CGPoint(
            x: lerp(leading, centered, spread),
            y: usableHeight - bounds.maxY
        )
    }

    /// 外接を容器に置いた矩形。`fanOrigin` と同じ位置。
    static func placedFanRect(
        fan: ExpandedFan,
        spread: CGFloat,
        fittingWidth: CGFloat,
        fittingHeight: CGFloat,
        depth: Int,
        bottomObstacle: CGFloat = 0,
        bottomClearance: CGFloat = 0
    ) -> CGRect {
        let bounds = geometry(fan: fan, spread: spread, depth: depth).bounds
        let origin = fanOrigin(
            fan: fan,
            spread: spread,
            fittingWidth: fittingWidth,
            fittingHeight: fittingHeight,
            depth: depth,
            bottomObstacle: bottomObstacle,
            bottomClearance: bottomClearance
        )
        return bounds.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// 券面の右下を容器の右下余白に揃えたあと、扇を `fanOrigin` へ動かす量。
    /// 運行終了と履歴は、たたんだ束の枠の右下をその点に置く。
    static func layerOffset(
        fan: ExpandedFan,
        spread: CGFloat,
        fittingWidth: CGFloat,
        fittingHeight: CGFloat,
        depth: Int,
        bottomObstacle: CGFloat = 0,
        bottomClearance: CGFloat = 0
    ) -> CGPoint {
        let snapshot = geometry(fan: fan, spread: spread, depth: depth)
        let origin = fanOrigin(
            fan: fan,
            spread: spread,
            fittingWidth: fittingWidth,
            fittingHeight: fittingHeight,
            depth: depth,
            bottomObstacle: bottomObstacle,
            bottomClearance: bottomClearance
        )
        let anchorX = fittingWidth - safeMargin
        let usableHeight = usableFanHeight(
            fittingHeight: fittingHeight,
            bottomObstacle: bottomObstacle,
            bottomClearance: bottomClearance
        )
        return CGPoint(
            x: origin.x - anchorX + snapshot.ticket.width,
            y: origin.y - usableHeight + snapshot.ticket.height
        )
    }

    private static func geometry(
        fan: ExpandedFan,
        spread: CGFloat,
        depth: Int
    ) -> (bounds: CGRect, ticket: CGSize) {
        let compact = compactTicketSize()
        let ticket = ticketSize(compact: compact, expanded: fan.ticket, spread: spread)
        let radius = lerp(compact.width * compactRadiusRatio, fan.radius, spread)
        let bounds = fanBounds(
            ticketWidth: ticket.width,
            ticketHeight: ticket.height,
            radius: radius,
            spread: spread,
            expandedStep: fan.stepDegrees,
            depthCap: max(0, depth)
        )
        return (bounds, ticket)
    }

    private static func collapsedOriginX(fan: ExpandedFan, fittingWidth: CGFloat, depth: Int) -> CGFloat {
        let bounds = geometry(fan: fan, spread: 0, depth: depth).bounds
        return fittingWidth - safeMargin - bounds.maxX
    }

    private static func centeredOriginX(fan: ExpandedFan, fittingWidth: CGFloat, depth: Int) -> CGFloat {
        let bounds = geometry(fan: fan, spread: 1, depth: depth).bounds
        let mid = (bounds.minX + bounds.maxX) / 2
        var dx = fittingWidth / 2 - mid
        if bounds.maxX + dx > fittingWidth {
            dx -= bounds.maxX + dx - fittingWidth
        }
        if bounds.minX + dx < 0 {
            dx -= bounds.minX + dx
        }
        return dx
    }

    private static func makeFan(width: CGFloat, scale: CGFloat, depth: Int) -> ExpandedFan {
        let height = MarsTicketSpec.height(forWidth: width)
        let clearance = min(
            expandedStepDegrees(ticketWidth: width, ticketHeight: height),
            maxExpandedStepDegrees
        )
        let unit = min(1, max(0, scale))
        let radius = width * compactRadiusRatio
            + (width * expandedRadiusRatio - width * compactRadiusRatio) * unit
        let step = compactStepDegrees + (clearance - compactStepDegrees) * Double(unit)
        let bounds = fanBounds(
            ticketWidth: width,
            ticketHeight: height,
            radius: radius,
            spread: 1,
            expandedStep: step,
            depthCap: depth
        )
        return ExpandedFan(
            ticket: CGSize(width: width, height: height),
            radius: radius,
            stepDegrees: step,
            cornerInset: CGSize(
                width: max(0, bounds.maxX - width) + safeMargin,
                height: max(0, bounds.maxY - height)
            )
        )
    }
}
