//
//  ApproachClearPanel.swift
//  Todo train
//
//  Compact Hub toy. The service strip stays readable. The needle stays still
//  until the player expands the panel and presses 開通. Judgement is the
//  press, not the release.
//

import SwiftUI
import UIKit

struct ApproachClearPanel: View {
    var world: ApproachClearWorld
    var interactionsFrozen: Bool

    @State private var engine = ApproachClearEngine()
    @State private var expanded = false
    @State private var haptics = ApproachClearHaptics()
    @State private var passFlight = 0
    @State private var bandPulse = false

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
            .saturation(world.inService ? 1 : 0.35)
        }
        .padding(10)
        .background(panelFill)
        .overlay {
            if world.paused {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TrainTheme.signalAmber.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(rimColor, lineWidth: engine.snapshot.flash == .none ? 1 : 2.5)
                .allowsHitTesting(false)
        }
        .overlay {
            if engine.snapshot.flash == .miss {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Ink.red.opacity(0.28), Ink.red.opacity(0.05), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 180
                        )
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .modifier(ClearanceShake(active: engine.snapshot.shake || engine.snapshot.jammed))
        .animation(TrainTheme.Motion.soft, value: expanded)
        .animation(.easeOut(duration: 0.06), value: engine.snapshot.flash)
        .allowsHitTesting(!interactionsFrozen)
        .onChange(of: world) { _, newWorld in
            engine.world = newWorld
            step()
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
                        .fill(Color.white.opacity(0.16))
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
        .task(id: ticking) {
            guard ticking else { return }
            while !Task.isCancelled {
                step()
                try? await Task.sleep(for: .milliseconds(16))
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
                color: world.dayEndPrompt && !world.inService ? TrainTheme.signalAmber : Ink.cyan,
                flash: engine.snapshot.flashRunningLamp && world.inService
            )
            statusCell(
                title: "運休",
                lit: !world.inService && !world.dayEndPrompt,
                color: Color.white.opacity(0.55),
                flash: false
            )
            statusCell(
                title: "停車",
                lit: world.paused,
                color: TrainTheme.signalAmber,
                flash: false
            )
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private func statusCell(title: String, lit: Bool, color: Color, flash: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(lit ? color : Color.white.opacity(0.12))
                .frame(width: 8, height: 8)
                .scaleEffect(flash ? 1.35 : 1)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(lit ? Color.white.opacity(0.92) : Color.white.opacity(0.38))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(lit ? color.opacity(0.14) : Color.white.opacity(0.03), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(lit ? "点灯" : "消灯")
    }

    private var lampRow: some View {
        HStack(spacing: 6) {
            toyLamp("接近", on: engine.snapshot.lamps.approach, color: Ink.cyan)
            toyLamp("良", on: engine.snapshot.lamps.perfect, color: Ink.gold)
            toyLamp("可", on: engine.snapshot.lamps.good, color: Ink.green)
            toyLamp("通", on: engine.snapshot.lamps.clear, color: Ink.green)
            toyLamp("否", on: engine.snapshot.lamps.reject, color: Ink.red)
            toyLamp("連", on: engine.snapshot.lamps.interlock, color: TrainTheme.signalAmber)
        }
    }

    private func toyLamp(_ title: String, on: Bool, color: Color) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(on ? color : Color.white.opacity(0.1))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.white.opacity(on ? 0.7 : 0.28))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var pips: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < engine.snapshot.pipsLit ? accentColor : Color.white.opacity(0.12))
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
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                if live {
                    span(bands.goodL, bands.goodR, width: width, color: Ink.green.opacity(0.34 * breath), height: 36)
                    span(bands.perfL, bands.perfR, width: width, color: Ink.gold.opacity(0.9 * breath), height: 36)
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 1, height: 40)
                        .offset(x: bands.center * width)
                    if engine.snapshot.easing {
                        span(bands.goodL, bands.goodR, width: width, color: Ink.cyan.opacity(0.22), height: 40)
                    }
                    if let press = engine.snapshot.pressU {
                        Circle()
                            .fill(markColor)
                            .frame(width: 6, height: 6)
                            .offset(x: press * width - 3)
                    }
                    if engine.snapshot.needleVisible {
                        let x = engine.snapshot.needle * width
                        if engine.snapshot.tier >= 2 {
                            Capsule()
                                .fill(needleColor.opacity(engine.snapshot.accent == .blaze ? 0.55 : 0.32))
                                .frame(width: max(14, width * 0.08), height: 3)
                                .offset(x: max(0, x - width * 0.08))
                        }
                        if bands.doubleBlip {
                            Circle()
                                .fill(needleColor.opacity(0.55))
                                .frame(width: 7, height: 7)
                                .shadow(color: needleColor.opacity(0.45), radius: 3)
                                .offset(x: max(0, engine.snapshot.needle - bands.ghostOffset) * width - 3.5)
                        }
                        NeedleChevron()
                            .fill(engine.snapshot.needleRejected ? Ink.red : needleColor)
                            .frame(width: 10, height: 7)
                            .shadow(color: needleColor.opacity(0.9), radius: 3)
                            .offset(x: x - 5, y: -20)
                        Capsule()
                            .fill(engine.snapshot.needleRejected ? Ink.red : needleColor)
                            .frame(width: 3, height: 44)
                            .shadow(color: (engine.snapshot.needleRejected ? Ink.red : needleColor).opacity(0.85), radius: 4)
                            .offset(x: x - 1.5)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white, needleColor, needleColor.opacity(0.2)],
                                    center: UnitPoint(x: 0.4, y: 0.35),
                                    startRadius: 0,
                                    endRadius: 6
                                )
                            )
                            .frame(width: 10, height: 10)
                            .shadow(color: needleColor.opacity(0.9), radius: 4)
                            .offset(x: x - 5)
                    }
                    if engine.snapshot.passing != nil {
                        passingTrain(width: width)
                    }
                }
            }
            .scaleEffect(x: engine.snapshot.shrinking ? 0.92 : 1, y: 1, anchor: .center)
            .frame(width: width, height: live ? 48 : 18)
        }
        .frame(height: live ? 48 : 18)
        .accessibilityHidden(true)
    }

    private func passingTrain(width: CGFloat) -> some View {
        let perfect = engine.snapshot.passing == .perfect
        return UnevenRoundedRectangle(
            topLeadingRadius: 2,
            bottomLeadingRadius: 2,
            bottomTrailingRadius: 5,
            topTrailingRadius: 5
        )
        .fill(
            LinearGradient(
                colors: perfect
                    ? [Color(red: 0.22, green: 0.2, blue: 0.08), Ink.gold]
                    : [Color(red: 0.14, green: 0.19, blue: 0.22), Ink.cyan],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .frame(width: 36, height: 12)
        .shadow(color: (perfect ? Ink.gold : Ink.green).opacity(0.7), radius: 5)
        .phaseAnimator([0, 1, 2], trigger: passFlight) { train, step in
            let fraction: CGFloat = step == 0 ? 0.08 : (step == 1 ? 0.48 : 0.82)
            train
                .offset(x: fraction * width)
                .opacity(step == 2 ? 0 : 1)
        } animation: { step in
            step == 0
                ? .linear(duration: 0.01)
                : .timingCurve(0.12, 0.82, 0.22, 1, duration: 0.14)
        }
    }

    private func span(_ start: Double, _ end: Double, width: CGFloat, color: Color, height: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, (end - start) * width), height: height)
            .offset(x: start * width)
    }

    private var interlockDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<ApproachClearTuning.interlockLamps, id: \.self) { index in
                Circle()
                    .fill(index < engine.snapshot.interlockLit ? TrainTheme.signalAmber : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.9))
                .frame(height: 68)
                .offset(y: 4)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.21, blue: 0.24),
                            buttonFill,
                            Color(red: 0.05, green: 0.07, blue: 0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 68)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 0, y: sunk ? 2 : 6)
                .shadow(color: armedGlow, radius: armedRadius)
                .offset(y: sunk ? 4 : 0)
            Text("開通")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Color.white.opacity(engine.snapshot.controlEnabled ? 0.94 : 0.35))
                .shadow(color: needleColor.opacity(0.35), radius: 6)
                .offset(y: sunk ? 4 : 0)
            ApproachClearTouchPad(
                enabled: engine.snapshot.controlEnabled && !interactionsFrozen,
                onDown: { handleDown() },
                onUp: { handleUp() },
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
                .fill(Color.white.opacity(0.08))
            Capsule()
                .fill(accentColor.opacity(0.85))
                .frame(width: max(0, geo.size.width * engine.snapshot.sessionProgress))
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var panelFill: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.12, blue: 0.14), Color(red: 0.05, green: 0.06, blue: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var accentColor: Color {
        switch engine.snapshot.accent {
        case .cyan, .warm: Ink.cyan
        case .hot, .blaze: Ink.gold
        }
    }

    private var needleColor: Color {
        switch engine.snapshot.accent {
        case .blaze, .hot: Ink.gold
        case .warm: Color(red: 0.45, green: 0.95, blue: 1)
        case .cyan: Ink.cyan
        }
    }

    private var rimColor: Color {
        switch engine.snapshot.flash {
        case .perfect: Ink.gold
        case .good: Ink.green
        case .miss: Ink.red
        case .none:
            switch engine.snapshot.accent {
            case .blaze: Ink.gold.opacity(0.75)
            case .hot: Ink.gold.opacity(0.45)
            case .warm: Ink.cyan.opacity(0.45)
            case .cyan: Ink.edge
            }
        }
    }

    private var armedGlow: Color {
        switch engine.snapshot.armed {
        case .perfect: Ink.gold.opacity(0.7)
        case .good: Ink.green.opacity(0.5)
        case .none: .clear
        }
    }

    private var armedRadius: CGFloat {
        switch engine.snapshot.armed {
        case .perfect: 12
        case .good: 8
        case .none: 0
        }
    }

    private var labelColor: Color {
        switch engine.snapshot.label {
        case "良": Ink.gold
        case "可": Ink.green
        case "早", "遅", "見送り": Ink.red
        default: Color.white.opacity(0.72)
        }
    }

    private var markColor: Color {
        switch engine.snapshot.label {
        case "良": Ink.gold
        case "可": Ink.green
        default: Ink.red
        }
    }

    private var buttonFill: Color {
        switch engine.snapshot.armed {
        case .perfect: Ink.gold.opacity(0.28)
        case .good: Ink.green.opacity(0.22)
        case .none: Color.white.opacity(engine.snapshot.contactDown ? 0.1 : 0.05)
        }
    }

    private func handleDown() {
        haptics.prepare()
        engine.world = world
        let cues = engine.touchDown(at: Self.milliseconds())
        if cues.contains(where: { cue in
            switch cue {
            case .perfect, .good: true
            default: false
            }
        }) {
            passFlight += 1
        }
        haptics.play(cues)
    }

    private func handleUp() {
        engine.world = world
        haptics.play(engine.touchUp(at: Self.milliseconds()))
    }

    private func step() {
        guard ticking else { return }
        engine.world = world
        haptics.play(engine.tick(at: Self.milliseconds()))
    }

    private func collapse() {
        haptics.stop()
        engine = ApproachClearEngine()
        withAnimation(TrainTheme.Motion.soft) {
            expanded = false
        }
    }

    private static func milliseconds() -> Double {
        CACurrentMediaTime() * 1_000
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

private enum Ink {
    static let edge = Color.white.opacity(0.12)
    static let cyan = Color(red: 0.20, green: 0.88, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.90, blue: 0.40)
    static let green = Color(red: 0.24, green: 1.0, blue: 0.54)
    static let red = Color(red: 1.0, green: 0.23, blue: 0.23)
}

private struct ApproachClearTouchPad: UIViewRepresentable {
    var enabled: Bool
    var onDown: () -> Void
    var onUp: () -> Void
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
    var onDown: () -> Void = {}
    var onUp: () -> Void = {}
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
        onDown()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch === tracked else { return }
        tracked = nil
        onUp()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked != nil else { return }
        tracked = nil
        onCancel()
    }
}
