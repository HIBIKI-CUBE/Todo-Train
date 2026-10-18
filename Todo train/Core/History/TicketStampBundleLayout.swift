//
//  TicketStampBundleLayout.swift
//  Todo train
//
//  束の縦重ね。奥の切符は上へ、傾きは付けない。
//

import CoreGraphics
import Foundation
import TodoTrainTicketUI

enum TicketStampBundleLayout {
    /// 1 段ごとののぞき。券面の高さに対する割合。
    static let peekRatio: CGFloat = 0.45
    static let standardMaxFanDepth = 4
    static let historyMaxFanDepth = 2
    /// 手前の切符だけ、指の横移動にこの割合で付く。
    static let dragFollow: CGFloat = 0.28
    /// 付随の上限。シャトルで大きく動かしても券面が流れ出さない。
    static let dragFollowLimit: CGFloat = 28
    static let fitInset: CGFloat = 10
    static let baseWidth: CGFloat = 300
    static let historyTicketHeight: CGFloat = 110
    /// 枠の高さと見た目の高さを揃える。幅 200 のままだとのぞく帯が券面の上ではなくなる。
    static var historyTicketWidth: CGFloat {
        historyTicketHeight * MarsTicketSpec.aspectWidth / MarsTicketSpec.aspectHeight
    }

    /// 角判。短辺に対する一辺、中心、見た目の傾き。
    static let cornerSealSideRatio: CGFloat = 0.38
    /// 0.80 だと所要の「30分」と右端の縦番号に乗る。左へ寄せ、下端は 45% の帯の中。
    static let cornerSealCenterXRatio: CGFloat = 0.66
    static let cornerSealCenterYRatio: CGFloat = 0.23
    static let cornerSealRotationDegrees: Double = -8

    static func maxFanDepth(for style: TicketStampBundleDeckStyle) -> Int {
        switch style {
        case .historyStrip:
            historyMaxFanDepth
        case .shutdown, .viewer:
            standardMaxFanDepth
        }
    }

    /// 手前を最新にしたときに見える奥行き。帯の高さと券面の縮尺に使う。
    static func stackDepth(
        stampCount: Int,
        focusIndex: Int,
        style: TicketStampBundleDeckStyle
    ) -> Int {
        guard stampCount > 0 else { return 0 }
        let maxDepth = maxFanDepth(for: style)
        let visibleCap = maxDepth + 1
        let focus = min(max(0, focusIndex), stampCount - 1)
        let visible = min(focus + 1, visibleCap)
        return min(max(0, visible - 1), maxDepth)
    }

    /// 奥の切符（depth > 0）は上へ。横の付随は手前だけ。
    static func offset(depth: Int, ticketHeight: CGFloat, drag: CGFloat = 0) -> CGSize {
        let capped = max(0, depth)
        let y = -peekRatio * ticketHeight * CGFloat(capped)
        let x: CGFloat = capped == 0 ? horizontalFollow(drag) : 0
        return CGSize(width: x, height: y)
    }

    static func horizontalFollow(_ drag: CGFloat) -> CGFloat {
        min(max(drag * dragFollow, -dragFollowLimit), dragFollowLimit)
    }

    static func bandHeight(ticketHeight: CGFloat, depth: Int) -> CGFloat {
        ticketHeight * (1 + peekRatio * CGFloat(max(0, depth)))
    }

    static func shutdownTargetWidth(containerWidth: CGFloat) -> CGFloat {
        min(max(0, containerWidth) * 0.72, 340)
    }

    struct TicketSize: Equatable {
        var width: CGFloat
        var height: CGFloat
        var scale: CGFloat
    }

    /// 幅の上限と、帯に収まる高さの小さい方。幅は高さから戻す。
    static func fittedTicketSize(
        targetWidth: CGFloat,
        viewportHeight: CGFloat,
        depth: Int
    ) -> TicketSize {
        let target = max(targetWidth, 1)
        let naturalH = MarsTicketSpec.height(forWidth: target)
        let factor = 1 + peekRatio * CGFloat(max(0, depth))
        let room = viewportHeight - fitInset
        let height = room > 0 ? min(naturalH, room / factor) : min(naturalH, 1)
        let width = height * MarsTicketSpec.aspectWidth / MarsTicketSpec.aspectHeight
        return TicketSize(width: width, height: height, scale: width / baseWidth)
    }

    /// 角判の外接矩形。回転後も券面座標。
    static func cornerSealBounds(
        ticketWidth: CGFloat,
        ticketHeight: CGFloat,
        sideRatio: CGFloat = cornerSealSideRatio,
        centerXRatio: CGFloat = cornerSealCenterXRatio,
        centerYRatio: CGFloat = cornerSealCenterYRatio,
        rotationDegrees: Double = -6
    ) -> CGRect {
        let short = min(ticketWidth, ticketHeight)
        let side = short * sideRatio
        let centerX = ticketWidth * centerXRatio
        let centerY = ticketHeight * centerYRatio
        let radians = rotationDegrees * Double.pi / 180
        let span = abs(cos(radians)) + abs(sin(radians))
        let half = (side / 2) * span
        return CGRect(x: centerX - half, y: centerY - half, width: half * 2, height: half * 2)
    }
}
