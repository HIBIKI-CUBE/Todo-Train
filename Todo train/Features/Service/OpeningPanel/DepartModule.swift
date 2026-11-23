//
//  DepartModule.swift
//  Todo train
//
//  DEPART の中身。ロック行の灯、流れる矢羽根、押し棒の段。
//  錠の行・窓・矢羽根の溝・押し棒の枠は格子が描く。
//

import SwiftUI

/// ロック行の灯と READY。地の刻印はそのまま、灯だけを載せる。
struct OpeningPanelLockPicture: Equatable {
    var master = false
    var clock = false
    var timetable = false
    var tickets = false
    var ready = false

    init(
        master: Bool = false,
        clock: Bool = false,
        timetable: Bool = false,
        tickets: Bool = false,
        ready: Bool = false
    ) {
        self.master = master
        self.clock = clock
        self.timetable = timetable
        self.tickets = tickets
        self.ready = ready
    }

    init(state: OpeningPanelState) {
        master = state.isLockLit(.master)
        clock = state.isLockLit(.clock)
        timetable = state.isLockLit(.timetable)
        tickets = state.isLockLit(.tickets)
        ready = state.readyLampLit
    }
}

extension OpeningPanelFace {
    var panelModule: OpeningPanelTokens.Module {
        switch self {
        case .sysbar: .sysbar
        case .master: .master
        case .clock: .clock
        case .clockKey: .clockKey
        case .timetable: .timetable
        case .nowBoard: .nowBoard
        case .tickets: .tickets
        case .load: .load
        case .comm: .comm
        case .depart: .depart
        }
    }
}

/// READY のあいだ、矢羽根が押し棒へ流れる波。参照モックの `waitStart`。
enum DepartChevronWave {
    static let steps: [TimeInterval] = [
        0.110, 0.090, 0.075, 0.062, 0.052, 0.044, 0.038, 0.033, 0.029, 0.026,
    ]
    static let hitHold: TimeInterval = 0.090
    static let rest: TimeInterval = 0.500
    static let count = OpeningPanelTokens.Chrome.chevronCount

    struct Sample: Equatable {
        var alphas: [Double]
        var columnHit: Bool
    }

    static var sweep: TimeInterval {
        steps.reduce(0, +)
    }

    static var period: TimeInterval {
        sweep + hitHold + rest
    }

    /// 絵が変わる位相。段の終わりと、当たりが消える瞬間。
    static var changePoints: [TimeInterval] {
        var points: [TimeInterval] = []
        var cursor: TimeInterval = 0
        for step in steps {
            cursor += step
            points.append(cursor)
        }
        points.append(cursor + hitHold)
        return points
    }

    /// 次に矢羽根の絵が変わる時刻。段のあいだは同じ絵なので、その間は描かない。
    static func nextFrameEdge(after date: Date) -> Date {
        let current = sample(at: date)
        return afterBoundary(rawEdge(after: date, points: changePoints, wrap: period)) {
            sample(at: $0) != current
        }
    }

    /// 次に押し棒の輪の当たりが変わる時刻。
    static func nextColumnEdge(after date: Date) -> Date {
        let current = sample(at: date).columnHit
        return afterBoundary(rawEdge(after: date, points: [sweep, sweep + hitHold], wrap: period + sweep)) {
            sample(at: $0).columnHit != current
        }
    }

    /// 境界の直後まで進める。和の端数で境界の手前に落ちると、絵が変わらない。
    private static func afterBoundary(_ date: Date, until changed: (Date) -> Bool) -> Date {
        var candidate = date.addingTimeInterval(0.000_2)
        for _ in 0..<6 where !changed(candidate) {
            candidate = candidate.addingTimeInterval(0.001)
        }
        return candidate
    }

    private static func rawEdge(after date: Date, points: [TimeInterval], wrap: TimeInterval) -> Date {
        let cycle = period
        guard cycle > 0 else { return date.addingTimeInterval(1) }
        var phase = date.timeIntervalSince(.distantPast).truncatingRemainder(dividingBy: cycle)
        if phase < 0 { phase += cycle }
        let epsilon = 0.000_05
        if let point = points.first(where: { $0 > phase + epsilon && $0 < cycle }) {
            return date.addingTimeInterval(point - phase)
        }
        let remaining = wrap - phase
        return date.addingTimeInterval(remaining > epsilon ? remaining : cycle)
    }

    static func sample(at date: Date, epoch: Date = .distantPast) -> Sample {
        let elapsed = date.timeIntervalSince(epoch)
        let cycle = period
        guard cycle > 0 else {
            return Sample(alphas: Array(repeating: 0, count: count), columnHit: false)
        }
        var phase = elapsed.truncatingRemainder(dividingBy: cycle)
        if phase < 0 { phase += cycle }
        return sample(elapsed: phase)
    }

    static func sample(elapsed: TimeInterval) -> Sample {
        var cursor: TimeInterval = 0
        for (index, step) in steps.enumerated() {
            if elapsed < cursor + step {
                return Sample(alphas: draw(head: index), columnHit: false)
            }
            cursor += step
        }
        if elapsed < cursor + hitHold {
            var alphas = Array(repeating: 0.0, count: count)
            let dimFrom = max(0, count - 3)
            for index in dimFrom..<count {
                alphas[index] = 0.30
            }
            alphas[count - 1] = 0.85
            return Sample(alphas: alphas, columnHit: true)
        }
        return Sample(alphas: Array(repeating: 0, count: count), columnHit: false)
    }

    /// `wDraw`。α はモックと同じく小数 2 桁。
    static func draw(head: Int) -> [Double] {
        let tail = min(3, 1 + head / 4)
        return (0..<count).map { index in
            let age = head - index
            guard age >= 0, age <= tail else { return 0 }
            let alpha = 0.85 * (1 - Double(age) / Double(tail + 1))
            return (alpha * 100).rounded() / 100
        }
    }
}

private struct DepartWaveDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var departWaveDate: Date? {
        get { self[DepartWaveDateKey.self] }
        set { self[DepartWaveDateKey.self] = newValue }
    }
}

/// 矢羽根の絵。段が同じあいだは等しい。
enum DepartChevronFrame: Equatable {
    case held
    case fill(Int)
    case off
    case wave([Double])

    static func make(
        flowing: Bool,
        heldDim: Bool,
        departed: Bool,
        fill: Int,
        date: Date
    ) -> DepartChevronFrame {
        if heldDim { return .held }
        if departed { return .fill(fill) }
        guard flowing else { return .off }
        return .wave(DepartChevronWave.sample(at: date).alphas)
    }

    var colors: [Color] {
        let count = OpeningPanelTokens.Chrome.chevronCount
        switch self {
        case .held:
            return Array(repeating: OpeningPanelTokens.Palette.chevronHeld, count: count)
        case .fill(let fill):
            return (0..<count).map { index in
                index < fill
                    ? OpeningPanelTokens.Palette.chevronLit
                    : OpeningPanelTokens.Palette.chevron
            }
        case .off:
            return Array(repeating: OpeningPanelTokens.Palette.chevron, count: count)
        case .wave(let alphas):
            return alphas.map { alpha in
                alpha > 0
                    ? OpeningPanelTokens.Palette.chevronFlow(alpha)
                    : OpeningPanelTokens.Palette.chevron
            }
        }
    }
}

/// 矢羽根 10 本。READY のあいだは段が変わるときだけ Canvas を描き、押したあとは手前から満ちる。
struct DepartChevronField: View {
    var state: OpeningPanelState

    @Environment(\.departWaveDate) private var waveDate

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("DepartChevronField")
        let flowing = state.chevronsFlowing
        let heldDim = state.chevronsHeldDim
        let departed = state.hasDeparted
        let fill = state.chevronFill
        Group {
            if flowing, waveDate == nil {
                DepartChevronPlayer()
            } else {
                DepartChevronCanvas(
                    frame: .make(
                        flowing: flowing,
                        heldDim: heldDim,
                        departed: departed,
                        fill: fill,
                        date: waveDate ?? .distantPast
                    )
                )
                .equatable()
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// 段の境だけ起こす。有限の TimelineSchedule は取り切ると止まり、`.animation` は表示リンクに乗る。
private struct DepartChevronPlayer: View {
    @State private var date = Date()

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("DepartChevronTick")
        DepartChevronCanvas(frame: .wave(DepartChevronWave.sample(at: date).alphas))
            .equatable()
            .task {
                await followWaveEdges(from: date, advance: DepartChevronWave.nextFrameEdge(after:)) {
                    date = $0
                }
            }
    }
}

/// 次の段まで寝てから日付を進める。表示リンクには載せず、予定を取り切っても止まらない。
private func followWaveEdges(
    from start: Date,
    advance: (Date) -> Date,
    apply: (Date) -> Void
) async {
    var cursor = start
    while !Task.isCancelled {
        let next = advance(cursor)
        let delay = max(next.timeIntervalSinceNow, 0.001)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard !Task.isCancelled else { return }
        cursor = Date()
        apply(cursor)
    }
}

private struct DepartChevronCanvas: View, Equatable {
    var frame: DepartChevronFrame

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("DepartChevronCanvas") { Self._printChanges() }
        Canvas { context, size in
            // 溝の内側いっぱいに描く。地の矢羽根は重ねない。
            let colors = frame.colors
            let count = colors.count
            guard count > 0, size.width > 0, size.height > 0 else { return }
            let gap: CGFloat = 2
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            guard width > 0 else { return }
            for index in 0..<count {
                let rect = CGRect(
                    x: CGFloat(index) * (width + gap),
                    y: 0,
                    width: width,
                    height: size.height
                )
                let path = OpeningPanelChevron().path(in: rect)
                context.fill(path, with: .color(colors[index]))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 押し棒の中の輪。波が当たった瞬間だけ色が変わる。
struct DepartColumnRing: View {
    var baseLit: Bool
    var flowing: Bool

    @Environment(\.departWaveDate) private var pinned

    var body: some View {
        if flowing, pinned == nil {
            DepartColumnHitPlayer(baseLit: baseLit)
        } else {
            let hit = flowing && (pinned.map { DepartChevronWave.sample(at: $0).columnHit } ?? false)
            stroke(baseLit || hit)
        }
    }

    private func stroke(_ lit: Bool) -> some View {
        DepartColumnStroke(lit: lit)
    }
}

private struct DepartColumnHitPlayer: View {
    var baseLit: Bool
    @State private var date = Date()

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("DepartColumnRing")
        DepartColumnStroke(lit: baseLit || DepartChevronWave.sample(at: date).columnHit)
            .task {
                await followWaveEdges(from: date, advance: DepartChevronWave.nextColumnEdge(after:)) {
                    date = $0
                }
            }
    }
}

private struct DepartColumnStroke: View {
    var lit: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(
                lit
                    ? OpeningPanelTokens.Palette.barColumnHit
                    : OpeningPanelTokens.Palette.barRingMid,
                lineWidth: 2
            )
            .padding(-3)
            .allowsHitTesting(false)
    }
}

/// DEPART の押し棒。沈みは唇の段で表し、枠そのものは格子が描く。
struct DepartModule: View {
    var state: OpeningPanelState
    var onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            OpeningPanelDepartLabel(
                depth: state.departBarDepth,
                markLit: state.departMarkLit
            )
            .animation(nil, value: state.departBarDepth)
            .animation(nil, value: state.departMarkLit)
        }
        .buttonStyle(.plain)
        .openingPanelAction(.depart, perform: onPress)
        .accessibilityLabel("DEPART")
        .accessibilityHint("Hub へ出ます")
    }
}

#Preview("押し棒") {
    let state = OpeningPanelState(
        scheduler: OpeningPanelDispatchScheduler(),
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: true
    )
    state.pressMaster()
    return OpeningPanelPushBar {
        DepartModule(state: state, onPress: { state.pressDepart() })
    }
    .frame(
        width: OpeningPanelTokens.Chrome.departBar.width,
        height: OpeningPanelTokens.Chrome.departBar.height
    )
    .padding()
    .background(OpeningPanelTokens.Palette.housing)
}
