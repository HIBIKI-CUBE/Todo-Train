//
//  ClockModule.swift
//  Todo train
//
//  7 セグメントの時計と、CLOCK の確認キー・12/24。
//  窓とキャップの地は格子が描く。桁の寸法は参照モックの最終 CSS。
//

import SwiftUI

enum OpeningPanelClockMetrics {
    static let digitWidth: CGFloat = 50
    static let digitHeight: CGFloat = 100
    static let horizontalSegment = CGSize(width: 38, height: 7)
    static let verticalSegment = CGSize(width: 7, height: 42)
    static let gap: CGFloat = 9
    static let colonWidth: CGFloat = 7
    static let colonHeight: CGFloat = 38
    static let colonBarHeight: CGFloat = 7
    static let faceWidth: CGFloat = 243
    static let faceHeight: CGFloat = 100
    /// `#clk` の `--ck`。窓の幅から 14、高さから 12 を引いて縮める。
    static let scaleWidthInset: CGFloat = 14
    static let scaleHeightInset: CGFloat = 12
    static let horizontalInset: CGFloat = 6
    static let verticalTop: CGFloat = 5
    static let middleTop: CGFloat = 46.5
    static let secondsFontSize: CGFloat = 11
    /// `letter-spacing: .04em`。
    static let secondsTrackingEm: CGFloat = 0.04
    static let secondsOpacity: Double = 0.8
    static let secondsTrailing: CGFloat = 7
    static let secondsBottom: CGFloat = 4

    static func scale(fitting size: CGSize) -> CGFloat {
        let width = size.width - scaleWidthInset
        let height = size.height - scaleHeightInset
        guard width > 0, height > 0 else { return 0 }
        return min(width / faceWidth, height / faceHeight)
    }
}

enum OpeningPanelClockSegment: CaseIterable, Hashable {
    case a, b, c, d, e, f, g
}

enum OpeningPanelClockGlyph {
    /// 参照モックの `MAP`。空白はどのセグも点かない。
    static func segments(for character: Character) -> Set<OpeningPanelClockSegment> {
        switch character {
        case "0": [.a, .b, .c, .d, .e, .f]
        case "1": [.b, .c]
        case "2": [.a, .b, .d, .e, .g]
        case "3": [.a, .b, .c, .d, .g]
        case "4": [.b, .c, .f, .g]
        case "5": [.a, .c, .d, .f, .g]
        case "6": [.a, .c, .d, .e, .f, .g]
        case "7": [.a, .b, .c]
        case "8": [.a, .b, .c, .d, .e, .f, .g]
        case "9": [.a, .b, .c, .d, .f, .g]
        default: []
        }
    }
}

enum OpeningPanelClockLayout {
    static func digitOrigin(_ index: Int) -> CGPoint {
        let step = OpeningPanelClockMetrics.digitWidth + OpeningPanelClockMetrics.gap
        let colonSpan = OpeningPanelClockMetrics.colonWidth + OpeningPanelClockMetrics.gap
        switch index {
        case 0:
            return .zero
        case 1:
            return CGPoint(x: step, y: 0)
        case 2:
            return CGPoint(x: step * 2 + colonSpan, y: 0)
        default:
            return CGPoint(x: step * 3 + colonSpan, y: 0)
        }
    }

    static func segment(_ segment: OpeningPanelClockSegment, digit index: Int) -> CGRect {
        let origin = digitOrigin(index)
        return localSegment(segment).offsetBy(dx: origin.x, dy: origin.y)
    }

    static func localSegment(_ segment: OpeningPanelClockSegment) -> CGRect {
        let metrics = OpeningPanelClockMetrics.self
        let horizontal = metrics.horizontalSegment
        let vertical = metrics.verticalSegment
        switch segment {
        case .a:
            return CGRect(x: metrics.horizontalInset, y: 0, width: horizontal.width, height: horizontal.height)
        case .g:
            return CGRect(
                x: metrics.horizontalInset,
                y: metrics.middleTop,
                width: horizontal.width,
                height: horizontal.height
            )
        case .d:
            return CGRect(
                x: metrics.horizontalInset,
                y: metrics.digitHeight - horizontal.height,
                width: horizontal.width,
                height: horizontal.height
            )
        case .f:
            return CGRect(x: 0, y: metrics.verticalTop, width: vertical.width, height: vertical.height)
        case .b:
            return CGRect(
                x: metrics.digitWidth - vertical.width,
                y: metrics.verticalTop,
                width: vertical.width,
                height: vertical.height
            )
        case .e:
            return CGRect(
                x: 0,
                y: metrics.digitHeight - metrics.verticalTop - vertical.height,
                width: vertical.width,
                height: vertical.height
            )
        case .c:
            return CGRect(
                x: metrics.digitWidth - vertical.width,
                y: metrics.digitHeight - metrics.verticalTop - vertical.height,
                width: vertical.width,
                height: vertical.height
            )
        }
    }

    static var colonOrigin: CGPoint {
        let x = (OpeningPanelClockMetrics.digitWidth + OpeningPanelClockMetrics.gap) * 2
        let y = (OpeningPanelClockMetrics.faceHeight - OpeningPanelClockMetrics.colonHeight) / 2
        return CGPoint(x: x, y: y)
    }

    static func colonBars() -> [CGRect] {
        let origin = colonOrigin
        let width = OpeningPanelClockMetrics.colonWidth
        let bar = OpeningPanelClockMetrics.colonBarHeight
        let height = OpeningPanelClockMetrics.colonHeight
        return [
            CGRect(x: origin.x, y: origin.y, width: width, height: bar),
            CGRect(x: origin.x, y: origin.y + height - bar, width: width, height: bar),
        ]
    }
}

struct OpeningPanelClockReadout: Equatable {
    var visible: Bool
    var pattern: String
    var colonLit: Bool
    var seconds: String?
    var spoken: String

    static func make(
        stage: OpeningPanelClockStage,
        cycle: OpeningPanelHourCycle,
        date: Date,
        calendar: Calendar
    ) -> OpeningPanelClockReadout {
        switch stage {
        case .dark:
            return OpeningPanelClockReadout(
                visible: false,
                pattern: "    ",
                colonLit: false,
                seconds: nil,
                spoken: "消灯"
            )
        case .backlight, .blank:
            return OpeningPanelClockReadout(
                visible: true,
                pattern: "    ",
                colonLit: false,
                seconds: nil,
                spoken: "起動中"
            )
        case .digits(let glyphs):
            return OpeningPanelClockReadout(
                visible: true,
                pattern: four(glyphs),
                colonLit: glyphs.count >= 2,
                seconds: nil,
                spoken: "起動中"
            )
        case .live:
            let pattern = hourMinute(at: date, cycle: cycle, calendar: calendar)
            let seconds = secondsText(at: date, calendar: calendar)
            return OpeningPanelClockReadout(
                visible: true,
                pattern: pattern,
                colonLit: millisecond(of: date) < 500,
                seconds: seconds,
                spoken: spokenTime(pattern: pattern, seconds: seconds)
            )
        }
    }

    static func hourMinute(at date: Date, cycle: OpeningPanelHourCycle, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let shown: Int
        switch cycle {
        case .twentyFour:
            shown = hour
        case .twelve:
            let wrapped = hour % 12
            shown = wrapped == 0 ? 12 : wrapped
        }
        return String(format: "%02d%02d", shown, minute)
    }

    static func secondsText(at date: Date, calendar: Calendar) -> String {
        String(format: "%02d", calendar.component(.second, from: date))
    }

    static func millisecond(of date: Date) -> Int {
        let fraction = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
        let positive = fraction < 0 ? fraction + 1 : fraction
        return min(999, Int(positive * 1_000))
    }

    private static func four(_ glyphs: String) -> String {
        String(glyphs.padding(toLength: 4, withPad: " ", startingAt: 0).prefix(4))
    }

    private static func spokenTime(pattern: String, seconds: String) -> String {
        let chars = Array(pattern)
        guard chars.count >= 4,
              let hour = Int(String(chars[0...1])),
              let minute = Int(String(chars[2...3])),
              let second = Int(seconds) else {
            return "起動中"
        }
        return "\(hour)時\(minute)分\(second)秒"
    }
}

enum OpeningPanelClockDrawer {
    struct Parts: OptionSet {
        let rawValue: Int
        static let digits = Parts(rawValue: 1 << 0)
        static let colon = Parts(rawValue: 1 << 1)
        static let all: Parts = [.digits, .colon]
    }

    /// 最終の `--glow` は `none`。点いた桁に影を付けない。
    static func draw(
        _ readout: OpeningPanelClockReadout,
        in context: inout GraphicsContext,
        size: CGSize,
        parts: Parts = .all
    ) {
        guard readout.visible else { return }
        let scale = OpeningPanelClockMetrics.scale(fitting: size)
        guard scale > 0 else { return }
        let faceWidth = OpeningPanelClockMetrics.faceWidth * scale
        let faceHeight = OpeningPanelClockMetrics.faceHeight * scale
        context.translateBy(x: (size.width - faceWidth) / 2, y: (size.height - faceHeight) / 2)
        context.scaleBy(x: scale, y: scale)
        if parts.contains(.digits) {
            let chars = Array(readout.pattern.prefix(4))
            for index in 0..<4 {
                let character = index < chars.count ? chars[index] : " "
                let lit = OpeningPanelClockGlyph.segments(for: character)
                for segment in OpeningPanelClockSegment.allCases {
                    let rect = OpeningPanelClockLayout.segment(segment, digit: index)
                    let color = lit.contains(segment)
                        ? OpeningPanelTokens.Palette.amber
                        : OpeningPanelTokens.Palette.amberDim
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        if parts.contains(.colon) {
            let colon = readout.colonLit ? OpeningPanelTokens.Palette.amber : OpeningPanelTokens.Palette.amberDim
            for bar in OpeningPanelClockLayout.colonBars() {
                context.fill(Path(bar), with: .color(colon))
            }
        }
    }
}

enum OpeningPanelClockTiming {
    static func floor(_ date: Date, step: TimeInterval) -> Date {
        let time = date.timeIntervalSinceReferenceDate
        let snapped = (time / step).rounded(.down) * step
        return Date(timeIntervalSinceReferenceDate: snapped)
    }
}

struct ClockModule: View {
    var state: OpeningPanelState

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("ClockModule")
        let stage = state.clockStage
        let cycle = state.hourCycle
        // 秒は 1 秒、コロンの点滅は 0.5 秒。`.animation` は表示リンクに乗り、盤の外まで落とす。
        if stage == .live {
            OpeningPanelLiveClock(cycle: cycle)
        } else {
            OpeningPanelClockFace(stage: stage, cycle: cycle, date: .distantPast)
        }
    }
}

/// 実時刻。桁と秒は 1 秒ごと、コロンだけ 0.5 秒ごと。
private struct OpeningPanelLiveClock: View {
    var cycle: OpeningPanelHourCycle
    private let secondStart: Date
    private let halfStart: Date

    init(cycle: OpeningPanelHourCycle, now: Date = .now) {
        self.cycle = cycle
        secondStart = OpeningPanelClockTiming.floor(now, step: 1)
        halfStart = OpeningPanelClockTiming.floor(now, step: 0.5)
    }

    var body: some View {
        ZStack {
            TimelineView(.periodic(from: secondStart, by: 1)) { context in
                let _ = OpeningPanelRedrawProbe.bump("ClockTick")
                let readout = OpeningPanelClockReadout.make(
                    stage: .live,
                    cycle: cycle,
                    date: context.date,
                    calendar: .current
                )
                ZStack {
                    OpeningPanelClockDigits(pattern: readout.pattern)
                        .equatable()
                    OpeningPanelClockSeconds(text: readout.seconds ?? "")
                        .equatable()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(readout.spoken)
            }
            TimelineView(.periodic(from: halfStart, by: 0.5)) { context in
                let _ = OpeningPanelRedrawProbe.bump("ClockColonTick")
                let lit = OpeningPanelClockReadout.millisecond(of: context.date) < 500
                OpeningPanelClockColon(lit: lit)
                    .equatable()
            }
        }
    }
}

private struct OpeningPanelClockDigits: View, Equatable {
    var pattern: String

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("OpeningPanelClockDigits") { Self._printChanges() }
        Canvas { context, size in
            let readout = OpeningPanelClockReadout(
                visible: true,
                pattern: pattern,
                colonLit: false,
                seconds: nil,
                spoken: ""
            )
            OpeningPanelClockDrawer.draw(readout, in: &context, size: size, parts: .digits)
        }
        .accessibilityHidden(true)
    }
}

private struct OpeningPanelClockColon: View, Equatable {
    var lit: Bool

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("OpeningPanelClockColon") { Self._printChanges() }
        Canvas { context, size in
            let readout = OpeningPanelClockReadout(
                visible: true,
                pattern: "    ",
                colonLit: lit,
                seconds: nil,
                spoken: ""
            )
            OpeningPanelClockDrawer.draw(readout, in: &context, size: size, parts: .colon)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct OpeningPanelClockSeconds: View, Equatable {
    var text: String

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("OpeningPanelClockSeconds")
        Text(text)
            .font(.system(size: OpeningPanelClockMetrics.secondsFontSize))
            .tracking(OpeningPanelClockMetrics.secondsFontSize * OpeningPanelClockMetrics.secondsTrackingEm)
            .monospacedDigit()
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
            .opacity(OpeningPanelClockMetrics.secondsOpacity)
            .lineLimit(1)
            .padding(.trailing, OpeningPanelClockMetrics.secondsTrailing)
            .padding(.bottom, OpeningPanelClockMetrics.secondsBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .accessibilityHidden(true)
    }
}

private struct OpeningPanelClockFace: View {
    var stage: OpeningPanelClockStage
    var cycle: OpeningPanelHourCycle
    var date: Date

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("OpeningPanelClockFace")
        let readout = OpeningPanelClockReadout.make(
            stage: stage,
            cycle: cycle,
            date: date,
            calendar: .current
        )
        Canvas { context, size in
            OpeningPanelClockDrawer.draw(readout, in: &context, size: size)
        }
        .overlay(alignment: .bottomTrailing) {
            if let seconds = readout.seconds {
                OpeningPanelClockSeconds(text: seconds)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(readout.spoken)
    }
}

struct ClockConfirmKey: View {
    var state: OpeningPanelState
    var onPress: () -> Void

    private var standbyAvailable: Bool {
        state.isPowered && state.confirmation(of: .clock) == .unconfirmed
    }

    private var okLit: Bool {
        guard state.isPowered else { return false }
        switch state.confirmation(of: .clock) {
        case .confirming, .confirmed:
            return true
        case .unconfirmed:
            return false
        }
    }

    var body: some View {
        Button(action: onPress) {
            OpeningPanelConfirmKey(
                topAvailable: standbyAvailable,
                bottomLit: okLit,
                sunk: okLit,
                showsNextEdge: state.nextAutomaticModule == .clock
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .openingPanelAction(.clockKey, perform: onPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CLOCK")
        .accessibilityValue(okLit ? "OK" : (standbyAvailable ? "STBY" : "消灯"))
        .accessibilityHint(hint)
    }

    private var hint: String {
        if !state.isPowered {
            return "電気が来ると確認できます"
        }
        if state.confirmation(of: .clock) == .unconfirmed {
            return "時計の確認を始めます"
        }
        return "時計の確認をやり直します"
    }
}

struct ClockHourModeKey: View {
    var state: OpeningPanelState
    var onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .openingPanelAction(.hourMode, perform: onPress)
        .accessibilityLabel("12/24")
        .accessibilityValue(state.hourCycle == .twelve ? "12時間" : "24時間")
        .accessibilityHint(
            state.hourCycle == .twelve
                ? "24時間表示に切り替えます"
                : "12時間表示に切り替えます"
        )
    }
}

private struct ClockPreviewPanel: View {
    let state: OpeningPanelState

    var body: some View {
        OpeningPanelGrid(
            master: {
                MasterModule(state: state) { state.pressMaster() }
            },
            clock: {
                ClockModule(state: state)
            },
            clockKey: {
                ClockConfirmKey(state: state) { state.pressConfirm(.clock) }
            },
            hourMode: {
                ClockHourModeKey(state: state) { state.pressHourMode() }
            },
            departBar: {
                DepartModule(state: state) { state.pressDepart() }
            }
        )
        .frame(width: OpeningPanelTokens.Phone.width, height: OpeningPanelTokens.Phone.height)
        .background(Color.black)
    }
}

@MainActor
private final class ClockPreviewScheduler: OpeningPanelScheduling {
    private struct Item {
        var id: Int
        var due: TimeInterval
        var action: () -> Void
    }

    private var now: TimeInterval = 0
    private var nextID = 0
    private var items: [Item] = []

    func schedule(after seconds: TimeInterval, execute: @escaping () -> Void) -> OpeningPanelTask {
        let id = nextID
        nextID += 1
        items.append(Item(id: id, due: now + seconds, action: execute))
        return OpeningPanelTask { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let index = items.indices.min(by: { items[$0].due < items[$1].due }),
              items[index].due <= target {
            let item = items.remove(at: index)
            now = item.due
            item.action()
        }
        now = target
    }
}

#Preview("消灯") {
    let state = OpeningPanelState(
        scheduler: ClockPreviewScheduler(),
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: true
    )
    return ClockPreviewPanel(state: state)
}

#Preview("実時刻") {
    let scheduler = ClockPreviewScheduler()
    let state = OpeningPanelState(
        scheduler: scheduler,
        feedback: OpeningPanelFeedbackSilent(),
        reduceMotion: true
    )
    state.pressMaster()
    state.pressConfirm(.clock)
    scheduler.advance(by: 1)
    return ClockPreviewPanel(state: state)
}
