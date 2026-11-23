//
//  LoadGauge.swift
//  Todo train
//
//  LOAD の積み。枠と FREE の地は格子が描き、ここは面だけを窓へ入れる。
//  色と余白は参照モックの `.gIn` `.gOv`。段の意味は仕様。
//

import SwiftUI

struct OpeningPanelLoadTarget: Equatable {
    var lit: Bool = false
    var freeMinutes: Double = 0
    var spanMinutes: Double = 1
    var tickets: [Double] = []

    static let dark = OpeningPanelLoadTarget()
}

enum OpeningPanelLoadWire {
    /// 盤が出す LOAD の目標。灯っていないときは切符の積みを空にする。
    static func target(
        lit: Bool,
        now: Date,
        rangeEndsAt: Date,
        freeMinutes: Int,
        ticketMinutes: [Int]
    ) -> OpeningPanelLoadTarget {
        let span = max(1, Int(rangeEndsAt.timeIntervalSince(now) / 60))
        return OpeningPanelLoadTarget(
            lit: lit,
            freeMinutes: Double(freeMinutes),
            spanMinutes: Double(span),
            tickets: lit ? ticketMinutes.map(Double.init) : []
        )
    }
}

struct OpeningPanelLoadSlab: Equatable, Identifiable {
    var id: Int
    /// 窓の下端からの割合。
    var bottom: CGFloat
    var height: CGFloat
    var overflow: Bool
}

struct OpeningPanelLoadDrawing: Equatable {
    var lit: Bool
    /// 窓の上端から、枠の上辺までの割合。
    var frameTop: CGFloat
    var slabs: [OpeningPanelLoadSlab]

    static let dark = OpeningPanelLoadDrawing(lit: false, frameTop: 0.36, slabs: [])
}

enum OpeningPanelLoadLogic {
    /// モックの `T` と下の余白。割合は 0...100。
    static let defaultTop = 36.0
    static let bottomMargin = 4.0
    static let minimumFrame = 22.0
    static let stackCap = 98.0
    /// `.gIn` `.gOv` の左右。
    static let barInset: CGFloat = 8

    static func isLit(powered: Bool, timetableConfirmed: Bool, ticketsConfirmed: Bool) -> Bool {
        powered && timetableConfirmed && ticketsConfirmed
    }

    static func drawing(_ target: OpeningPanelLoadTarget) -> OpeningPanelLoadDrawing {
        guard target.lit else { return .dark }
        let placed = placement(freeMinutes: target.freeMinutes, spanMinutes: target.spanMinutes)
        var slabs: [OpeningPanelLoadSlab] = []
        var cursor = bottomMargin
        for (index, minutes) in target.tickets.enumerated() {
            let next = cursor + max(0, minutes) * placed.unit
            let fittedEnd = min(next, placed.topFromBottom)
            append(
                &slabs,
                index: index * 2,
                from: cursor,
                to: fittedEnd,
                overflow: false
            )
            append(
                &slabs,
                index: index * 2 + 1,
                from: max(cursor, placed.topFromBottom),
                to: next,
                overflow: true
            )
            cursor = next
        }
        return OpeningPanelLoadDrawing(
            lit: true,
            frameTop: placed.frameTop,
            slabs: slabs
        )
    }

    /// 区切りや空きが変わるときの途中。切符の長さは届いた値を使い、枚数と空きだけを寄せる。
    static func interpolate(
        from: OpeningPanelLoadTarget,
        to: OpeningPanelLoadTarget,
        step: Int
    ) -> OpeningPanelLoadTarget {
        guard to.lit, from.lit else { return to }
        let steps = OpeningPanelTiming.loadSteps
        let current = min(max(step, 1), steps)
        if current >= steps { return to }
        let unit = Double(current) / Double(steps)
        let free = from.freeMinutes + (to.freeMinutes - from.freeMinutes) * unit
        let count = interpolatedCount(from: from.tickets.count, to: to.tickets.count, step: current)
        return OpeningPanelLoadTarget(
            lit: true,
            freeMinutes: free,
            spanMinutes: to.spanMinutes,
            tickets: Array(to.tickets.prefix(count))
        )
    }

    static func interpolatedCount(from: Int, to: Int, step: Int) -> Int {
        let steps = OpeningPanelTiming.loadSteps
        if step >= steps { return to }
        if to >= from {
            let added = Int((Double(to - from) * Double(step) / Double(steps)).rounded(.up))
            return min(to, from + added)
        }
        let removed = Int((Double(from - to) * Double(step) / Double(steps)).rounded(.up))
        return max(to, from - removed)
    }

    private struct Placement {
        var unit: Double
        var topFromBottom: Double
        var frameTop: CGFloat
    }

    private static func placement(freeMinutes: Double, spanMinutes: Double) -> Placement {
        let span = max(1, spanMinutes)
        let free = max(0, freeMinutes)
        let body = 100 - defaultTop - bottomMargin
        let unit = free > 0 ? max(body / span, minimumFrame / free) : body / span
        let topFromBottom = bottomMargin + free * unit
        let frameTop = min(1, max(0, (100 - topFromBottom) / 100))
        return Placement(unit: unit, topFromBottom: topFromBottom, frameTop: frameTop)
    }

    private static func append(
        _ slabs: inout [OpeningPanelLoadSlab],
        index: Int,
        from: Double,
        to: Double,
        overflow: Bool
    ) {
        let start = min(from, stackCap)
        let end = min(to, stackCap)
        guard end > start else { return }
        slabs.append(
            OpeningPanelLoadSlab(
                id: index,
                bottom: start / 100,
                height: (end - start) / 100,
                overflow: overflow
            )
        )
    }
}

@MainActor
@Observable
final class OpeningPanelLoadPlayer {
    private let scheduler: any OpeningPanelScheduling
    private(set) var sample: OpeningPanelLoadTarget = .dark
    /// 段が進んだとき。SwiftUI は @State のクラスの変更だけでは窓を描き直さないことがある。
    @ObservationIgnored
    var onSample: (@MainActor () -> Void)?
    private var committed: OpeningPanelLoadTarget = .dark
    private var tasks: [OpeningPanelTask] = []
    private var generation = 0

    init(scheduler: any OpeningPanelScheduling) {
        self.scheduler = scheduler
    }

    func set(_ target: OpeningPanelLoadTarget) {
        let from = committed
        guard target != from else { return }
        committed = target
        generation += 1
        tasks.forEach { $0.cancel() }
        tasks = []
        guard target.lit, from.lit else {
            publish(target)
            return
        }
        let generation = generation
        publish(OpeningPanelLoadLogic.interpolate(from: from, to: target, step: 1))
        guard OpeningPanelTiming.loadSteps > 1 else { return }
        for step in 2...OpeningPanelTiming.loadSteps {
            let delay = OpeningPanelTiming.loadStep * Double(step - 1)
            let task = scheduler.schedule(after: delay) { [weak self] in
                guard let self, self.generation == generation else { return }
                self.publish(OpeningPanelLoadLogic.interpolate(from: from, to: target, step: step))
            }
            tasks.append(task)
        }
    }

    private func publish(_ next: OpeningPanelLoadTarget) {
        sample = next
        onSample?()
    }
}

struct LoadGauge: View {
    var drawing: OpeningPanelLoadDrawing

    var body: some View {
        GeometryReader { geo in
            if drawing.lit {
                ForEach(drawing.slabs) { slab in
                    Rectangle()
                        .fill(slab.overflow ? OpeningPanelTokens.Palette.amber : OpeningPanelTokens.Palette.gaugeFit)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x17 / 255))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, OpeningPanelLoadLogic.barInset)
                        .frame(height: max(0, geo.size.height * slab.height))
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * (1 - slab.bottom - slab.height / 2)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
