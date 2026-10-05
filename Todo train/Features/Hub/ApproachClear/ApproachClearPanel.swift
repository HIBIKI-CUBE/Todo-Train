//
//  ApproachClearPanel.swift
//  Todo train
//
//  Compact Hub instrument on the grouped surface. The toy uses the rail;
//  signal colors stay on the real service strip. The needle stays still
//  until the player expands the panel and presses 開通. Judgement is the
//  press, not the release.
//

import SwiftUI
import UIKit

struct ApproachClearPanel: View {
    var world: ApproachClearWorld
    var interactionsFrozen: Bool

    @State private var engine = ApproachClearPanel.liveEngine()
    @State private var expanded = false
    @State private var haptics = ApproachClearHaptics()
    @State private var bandPulse = false
    @State private var sweepStartMs = 0.0
    @State private var sweepPerfect = false
    @State private var ghostGoodL = 0.0
    @State private var ghostGoodR = 0.0
    @State private var ghostUntilMs = 0.0
    @State private var barrierStartMs = 0.0
    /// Media time shared with the finger. The needle is drawn for this instant.
    @State private var presentationMs = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            serviceStrip

            Group {
                if expanded {
                    expandedBody
                } else {
                    collapsedBody
                }
            }
            .opacity(world.inService ? 1 : 0.42)
        }
        .padding(10)
        .background(panelFill)
        .overlay {
            if world.paused {
                RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                    .fill(TrainTheme.signalAmber.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                .strokeBorder(rimColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous))
        .modifier(ClearanceShake(active: engine.snapshot.shake || engine.snapshot.jammed))
        .animation(TrainTheme.Motion.soft, value: expanded)
        .animation(.easeOut(duration: 0.06), value: engine.snapshot.flash)
        .allowsHitTesting(!interactionsFrozen)
        .onChange(of: world) { _, newWorld in
            engine.world = newWorld
            step()
        }
        .onChange(of: engine.snapshot.bands) { old, _ in
            guard old.goodR > old.goodL else { return }
            ghostGoodL = old.goodL
            ghostGoodR = old.goodR
            ghostUntilMs = Self.milliseconds() + 400
        }
        .onChange(of: engine.snapshot.barrierOn) { _, on in
            if on { barrierStartMs = Self.milliseconds() }
        }
        .onChange(of: engine.snapshot.idleBreath) { _, breathing in
            if breathing {
                bandPulse = false
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    bandPulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    bandPulse = false
                }
            }
        }
        .onChange(of: interactionsFrozen) { _, frozen in
            let now = Self.milliseconds()
            if frozen {
                engine.freeze(at: now)
                haptics.stop()
            } else {
                engine.thaw(at: now)
            }
        }
        .onDisappear { haptics.stop() }
        .accessibilityElement(children: .contain)
    }

    private var collapsedBody: some View {
        Button {
            haptics.prepare()
            withAnimation(TrainTheme.Motion.soft) {
                expanded = true
            }
        } label: {
            track(live: false)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("接近クリアランス")
        .accessibilityHint("開く")
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                lampRow
                Spacer(minLength: 4)
                pips
                Button {
                    collapse()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("閉じる")
            }

            ZStack {
                track(live: true)
                if engine.snapshot.phase == .interlock {
                    interlockDots
                }
                if engine.snapshot.barrierOn {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 52)

            Text(engine.snapshot.label)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                .accessibilityHidden(engine.snapshot.label.isEmpty)

            if let calm = engine.snapshot.calm {
                calmBlock(calm)
            } else {
                clearanceButton
            }

            sessionBar

            #if DEBUG
            Text(engine.snapshot.debug.line)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            #endif
        }
        .background {
            ApproachClearDisplayLink(active: ticking) { now in
                presentationMs = now
                step(at: now)
            }
        }
    }

    private var ticking: Bool {
        expanded
            && !interactionsFrozen
            && engine.snapshot.phase != .dormant
            && engine.snapshot.phase != .calm
    }

    private var serviceStrip: some View {
        HStack(spacing: 6) {
            statusCell(
                title: "運行中",
                lit: world.inService || world.dayEndPrompt,
                color: world.dayEndPrompt && !world.inService ? TrainTheme.signalAmber : TrainTheme.signalGreen
            )
            statusCell(
                title: "運休",
                lit: !world.inService && !world.dayEndPrompt,
                color: TrainTheme.muted
            )
            statusCell(
                title: "停車",
                lit: world.paused,
                color: TrainTheme.signalAmber
            )
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private func statusCell(title: String, lit: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(lit ? color : Color(uiColor: .quaternarySystemFill))
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(lit ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(lit ? color.opacity(0.12) : Color.clear, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(lit ? "点灯" : "消灯")
    }

    private var lampRow: some View {
        let lamps = engine.snapshot.lamps
        let row: [(String, Bool)] = [
            ("接近", lamps.approach),
            ("良", lamps.perfect),
            ("可", lamps.good),
            ("通", lamps.clear),
            ("否", lamps.reject),
            ("連", lamps.interlock),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, lamp in
                toyLamp(lamp.0, on: lamp.1)
            }
        }
    }

    private func toyLamp(_ title: String, on: Bool) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(on ? TrainTheme.rail : Color(uiColor: .quaternarySystemFill))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(on ? Color.secondary : Color.secondary.opacity(0.45))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var pips: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < engine.snapshot.pipsLit ? TrainTheme.rail : Color(uiColor: .quaternarySystemFill))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func track(live: Bool) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let bands = engine.snapshot.bands
            let breath = engine.snapshot.idleBreath ? (bandPulse ? 1.0 : 0.62) : 1.0
            let rejected = engine.snapshot.flash == .miss || engine.snapshot.needleRejected
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemFill))
                Capsule()
                    .fill(TrainTheme.track)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                if live {
                    let ink = rejected ? Color.primary : TrainTheme.rail
                    if presentationMs < ghostUntilMs, ghostGoodR > ghostGoodL {
                        let fade = max(0, (ghostUntilMs - presentationMs) / 400)
                        window(
                            ghostGoodL,
                            ghostGoodR,
                            width: width,
                            fill: Color.clear,
                            stroke: TrainTheme.track.opacity(fade),
                            height: 40,
                            dashed: true
                        )
                        .opacity(fade)
                    }
                    Group {
                        window(
                            bands.goodL,
                            bands.goodR,
                            width: width,
                            fill: ink.opacity(0.16 * breath),
                            stroke: ink.opacity(rejected ? 0.7 : 0.4),
                            height: 36,
                            dashed: false
                        )
                        window(
                            bands.perfL,
                            bands.perfR,
                            width: width,
                            fill: ink.opacity(0.38),
                            stroke: ink,
                            height: 36,
                            dashed: false
                        )
                        Rectangle()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: 1, height: 44)
                            .offset(x: bands.center * width)
                    }
                    .animation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.22), value: bands)
                    if let press = engine.snapshot.pressU {
                        Rectangle()
                            .fill(markColor)
                            .frame(width: 1, height: 46)
                            .offset(x: press * width)
                    }
                    Group {
                        if engine.snapshot.needleVisible {
                            let needleU = shownNeedle
                            let x = needleU * width
                            let mark = engine.snapshot.needleRejected ? Color.primary : TrainTheme.rail
                            if bands.doubleBlip {
                                Circle()
                                    .fill(mark.opacity(0.35))
                                    .frame(width: 7, height: 7)
                                    .offset(x: max(0, needleU - bands.ghostOffset) * width - 3.5)
                            }
                            NeedleChevron()
                                .fill(mark)
                                .frame(width: 8, height: 5)
                                .offset(x: x - 4, y: -18)
                            Capsule()
                                .fill(mark)
                                .frame(width: 2, height: 40)
                                .offset(x: x - 1)
                            Circle()
                                .fill(mark)
                                .frame(width: 8, height: 8)
                                .offset(x: x - 4)
                        }
                    }
                    .animation(nil, value: shownNeedle)
                    .transaction { $0.disablesAnimations = true }
                    if let progress = sweepProgress {
                        rushingLight(width: width, progress: progress)
                    }
                    barrierFlash(width: width)
                }
            }
            .scaleEffect(x: engine.snapshot.shrinking ? 0.92 : 1, y: 1, anchor: .center)
            .frame(width: width, height: live ? 48 : 18)
        }
        .frame(height: live ? 48 : 18)
        .accessibilityHidden(true)
    }

    private func rushingLight(width: CGFloat, progress: Double) -> some View {
        let travel = 0.06 + 0.78 * (1 - pow(1 - min(1, progress), 2.4))
        let fade = progress < 0.55 ? 1.0 : max(0, 1 - (progress - 0.55) / 0.45)
        let head = travel * width
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(TrainTheme.rail.opacity(0.28))
                .frame(width: 28, height: 4)
                .offset(x: head - 22)
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 2,
                bottomTrailingRadius: 4,
                topTrailingRadius: 4
            )
            .fill(TrainTheme.rail.opacity(sweepPerfect ? 1 : 0.72))
            .frame(width: 28, height: 8)
            .offset(x: head)
        }
        .opacity(fade)
        .allowsHitTesting(false)
    }

    private func barrierFlash(width: CGFloat) -> some View {
        let elapsed = presentationMs - barrierStartMs
        let t = elapsed / 220
        return Group {
            if barrierStartMs > 0, t >= 0, t < 1 {
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: width * 0.18, height: 48)
                    .offset(x: (t * 1.2 - 0.2) * width)
                    .opacity(t < 0.2 ? t / 0.2 : 1 - t)
                    .allowsHitTesting(false)
            }
        }
    }

    private func window(
        _ start: Double,
        _ end: Double,
        width: CGFloat,
        fill: Color,
        stroke: Color,
        height: CGFloat,
        dashed: Bool
    ) -> some View {
        let span = max(0, (end - start) * width)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(
                        stroke,
                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])
                    )
            }
            .frame(width: span, height: height)
            .offset(x: start * width)
    }

    private var interlockDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<ApproachClearTuning.interlockLamps, id: \.self) { index in
                let lit = index < engine.snapshot.interlockLit
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(lit ? TrainTheme.rail : Color(uiColor: .quaternarySystemFill))
                    .frame(width: 8, height: lit ? 14 : 8)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var clearanceButton: some View {
        GeometryReader { geo in
            lever
                .frame(width: geo.size.width * 0.74, height: 76)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 76)
    }

    private var lever: some View {
        let sunk = engine.snapshot.contactDown
        return ZStack {
            RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 68)
                .offset(y: 4)
            RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                .fill(buttonFill)
                .frame(height: 68)
                .overlay {
                    RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
                        .strokeBorder(TrainTheme.track, lineWidth: 1)
                }
                .offset(y: sunk ? 4 : 0)
            Text("開通")
                .font(.title3.weight(.semibold))
                .foregroundStyle(engine.snapshot.controlEnabled ? Color.primary : Color.secondary)
                .offset(y: sunk ? 4 : 0)
            ApproachClearTouchPad(
                enabled: engine.snapshot.controlEnabled && !interactionsFrozen,
                onDown: { handleDown(at: $0) },
                onUp: { handleUp(at: $0) },
                onCancel: { engine.touchCancel() }
            )
        }
        .opacity(engine.snapshot.controlEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.04), value: sunk)
    }

    private func calmBlock(_ calm: ApproachClearCalm) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(calm == .full ? "満線" : "閑散")
                .font(.subheadline.weight(.semibold))
            Text(calm == .full ? "回送は満ちた · また近づくとき" : "回送おわり · また近づくとき")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("再開") {
                engine.world = world
                engine.restart(at: Self.milliseconds())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color(uiColor: .quaternarySystemFill))
            Capsule()
                .fill(accentColor.opacity(0.85))
                .frame(width: max(0, geo.size.width * engine.snapshot.sessionProgress))
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var panelFill: some View {
        TrainTheme.surface
    }

    private var accentColor: Color {
        TrainTheme.rail
    }

    private var rimColor: Color {
        switch engine.snapshot.flash {
        case .perfect, .good: TrainTheme.rail
        case .miss: Color.primary.opacity(0.45)
        case .none: TrainTheme.track
        }
    }

    private var labelColor: Color {
        switch engine.snapshot.label {
        case "良", "可": TrainTheme.rail
        case "早", "遅", "見送り": Color.primary
        default: Color.secondary
        }
    }

    private var markColor: Color {
        switch engine.snapshot.label {
        case "良", "可": TrainTheme.rail
        default: Color.primary
        }
    }

    private var buttonFill: Color {
        switch displayedArm {
        case .perfect, .good:
            TrainTheme.rail.opacity(engine.snapshot.contactDown ? 0.22 : 0.14)
        case .none:
            Color(uiColor: .tertiarySystemGroupedBackground)
        }
    }

    private var sweepProgress: Double? {
        guard sweepStartMs > 0, presentationMs >= sweepStartMs else { return nil }
        let elapsed = presentationMs - sweepStartMs
        guard elapsed < 300 else { return nil }
        return elapsed / 280
    }

    /// Needle position at the same media time as the finger. Predicting the
    /// next frame put the needle ahead of the press, and the lead jumped
    /// whenever a frame was missed.
    private var shownNeedle: Double {
        let snap = engine.snapshot
        guard snap.phase == .approach, presentationMs > 0, snap.bands.approachMs > 0 else {
            return snap.needle
        }
        let u = (presentationMs - snap.approachStart) / snap.bands.approachMs
        return min(1, max(0, u))
    }

    private var displayedArm: ApproachClearArm {
        guard engine.snapshot.phase == .approach else { return .none }
        return switch engine.snapshot.bands.zone(at: shownNeedle) {
        case .perfect: .perfect
        case .good: .good
        case .out: .none
        }
    }

    private func handleDown(at milliseconds: Double) {
        engine.world = world
        let cues = engine.touchDown(at: milliseconds)
        var perfect = false
        var cleared = false
        for cue in cues {
            switch cue {
            case .perfect:
                perfect = true
                cleared = true
            case .good:
                cleared = true
            default:
                break
            }
        }
        if cleared {
            sweepStartMs = Self.milliseconds()
            sweepPerfect = perfect
        }
        haptics.prepare()
        haptics.play(cues)
    }

    private func handleUp(at milliseconds: Double) {
        engine.world = world
        haptics.play(engine.touchUp(at: milliseconds))
    }

    private func step(at now: Double = Self.milliseconds()) {
        guard ticking else { return }
        engine.world = world
        haptics.play(engine.tick(at: now))
    }

    private func collapse() {
        haptics.stop()
        engine = Self.liveEngine()
        sweepStartMs = 0
        withAnimation(TrainTheme.Motion.soft) {
            expanded = false
        }
    }

    private static func liveEngine() -> ApproachClearEngine {
        var engine = ApproachClearEngine()
        engine.liveRandom = true
        return engine
    }

    private static func milliseconds() -> Double {
        CACurrentMediaTime() * 1_000
    }
}

private struct ApproachClearDisplayLink: UIViewRepresentable {
    var active: Bool
    var onFrame: (Double) -> Void

    func makeUIView(context: Context) -> ApproachClearDisplayLinkView {
        let view = ApproachClearDisplayLinkView()
        view.onFrame = onFrame
        view.active = active
        return view
    }

    func updateUIView(_ uiView: ApproachClearDisplayLinkView, context: Context) {
        uiView.onFrame = onFrame
        uiView.active = active
    }

    static func dismantleUIView(_ uiView: ApproachClearDisplayLinkView, coordinator: ()) {
        uiView.active = false
    }
}

private final class ApproachClearDisplayLinkView: UIView {
    var onFrame: (Double) -> Void = { _ in }
    var active = false {
        didSet {
            guard active != oldValue else { return }
            if active {
                guard link == nil else { return }
                let link = CADisplayLink(target: self, selector: #selector(fire(_:)))
                link.add(to: .main, forMode: .common)
                self.link = link
            } else {
                link?.invalidate()
                link = nil
            }
        }
    }

    private var link: CADisplayLink?

    @objc private func fire(_ link: CADisplayLink) {
        // targetTimestamp sits a full vsync ahead and leaps when a frame is
        // dropped, so the needle met the window before the finger.
        _ = link
        onFrame(CACurrentMediaTime() * 1_000)
    }

    deinit {
        link?.invalidate()
    }
}

private struct NeedleChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct ClearanceShake: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: active ? 5 : 0)
            .animation(
                active
                    ? .linear(duration: 0.04).repeatCount(5, autoreverses: true)
                    : .easeOut(duration: 0.05),
                value: active
            )
    }
}

private struct ApproachClearTouchPad: UIViewRepresentable {
    var enabled: Bool
    var onDown: (Double) -> Void
    var onUp: (Double) -> Void
    var onCancel: () -> Void

    func makeUIView(context: Context) -> ApproachClearTouchView {
        let view = ApproachClearTouchView()
        view.onDown = onDown
        view.onUp = onUp
        view.onCancel = onCancel
        view.isUserInteractionEnabled = enabled
        return view
    }

    func updateUIView(_ uiView: ApproachClearTouchView, context: Context) {
        uiView.onDown = onDown
        uiView.onUp = onUp
        uiView.onCancel = onCancel
        uiView.isUserInteractionEnabled = enabled
    }
}

private final class ApproachClearTouchView: UIView {
    var onDown: (Double) -> Void = { _ in }
    var onUp: (Double) -> Void = { _ in }
    var onCancel: () -> Void = {}
    private var tracked: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "開通"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled, tracked == nil, let touch = touches.first else { return }
        tracked = touch
        onDown(touch.timestamp * 1_000)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch === tracked else { return }
        tracked = nil
        onUp(touch.timestamp * 1_000)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked != nil else { return }
        tracked = nil
        onCancel()
    }
}
