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

/// 矢羽根 10 本。READY のあいだは `TimelineView` で流し、押したあとは手前から満ちる。
struct DepartChevronField: View {
    var state: OpeningPanelState

    @Environment(\.departWaveDate) private var waveDate

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !state.chevronsFlowing || waveDate != nil
            )
        ) { context in
            chevrons(at: waveDate ?? context.date)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func chevrons(at date: Date) -> some View {
        Canvas { context, size in
            // 溝の内側いっぱいに描く。地の矢羽根は重ねない。
            let colors = chevronColors(at: date)
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

    private func chevronColors(at date: Date) -> [Color] {
        let count = OpeningPanelTokens.Chrome.chevronCount
        if state.chevronsHeldDim {
            return Array(repeating: OpeningPanelTokens.Palette.chevronHeld, count: count)
        }
        if state.hasDeparted {
            return (0..<count).map { index in
                index < state.chevronFill
                    ? OpeningPanelTokens.Palette.chevronLit
                    : OpeningPanelTokens.Palette.chevron
            }
        }
        guard state.chevronsFlowing else {
            return Array(repeating: OpeningPanelTokens.Palette.chevron, count: count)
        }
        return DepartChevronWave.sample(at: date).alphas.map { alpha in
            alpha > 0
                ? OpeningPanelTokens.Palette.chevronFlow(alpha)
                : OpeningPanelTokens.Palette.chevron
        }
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
