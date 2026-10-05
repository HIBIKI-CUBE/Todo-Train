//
//  ApproachClearPanel.swift
//  Todo train
//
//  Compact Hub toy. The service strip stays readable. The needle stays still
//  until the player expands the panel and touches 開通.
//

import SwiftUI
import UIKit

struct ApproachClearPanel: View {
    var world: ApproachClearWorld
    var interactionsFrozen: Bool

    @State private var engine = ApproachClearEngine()
    @State private var expanded = false
    @State private var haptics = ApproachClearHaptics()

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
                .strokeBorder(flashColor, lineWidth: engine.snapshot.flash == .none ? 1 : 2)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(TrainTheme.Motion.soft, value: expanded)
        .animation(TrainTheme.Motion.soft, value: engine.snapshot.flash)
        .allowsHitTesting(!interactionsFrozen)
        .onChange(of: world) { _, newWorld in
            engine.world = newWorld
            step()
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
            .frame(height: 36)

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
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                if live {
                    span(bands.goodL, bands.goodR, width: width, color: Ink.green.opacity(0.28), height: 22)
                    span(bands.perfL, bands.perfR, width: width, color: Ink.gold.opacity(0.85), height: 22)
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1, height: 26)
                        .offset(x: bands.center * width)
                    if engine.snapshot.easing {
                        span(bands.goodL, bands.goodR, width: width, color: Ink.cyan.opacity(0.2), height: 26)
                    }
                    if let press = engine.snapshot.pressU {
                        Circle()
                            .fill(markColor)
                            .frame(width: 6, height: 6)
                            .offset(x: press * width - 3)
                    }
                    if engine.snapshot.bands.doubleBlip, engine.snapshot.needleVisible {
                        Circle()
                            .fill(Ink.cyan.opacity(0.35))
                            .frame(width: 8, height: 8)
                            .offset(x: max(0, engine.snapshot.needle - engine.snapshot.bands.ghostOffset) * width - 4)
                    }
                    if engine.snapshot.needleVisible {
                        Capsule()
                            .fill(engine.snapshot.needleRejected ? Ink.red : needleColor)
                            .frame(width: 3, height: 30)
                            .offset(x: engine.snapshot.needle * width - 1.5)
                    }
                    if engine.snapshot.passing != nil {
                        Capsule()
                            .fill(engine.snapshot.passing == .perfect ? Ink.gold : Ink.green)
                            .frame(width: 18, height: 8)
                            .offset(x: min(width - 18, engine.snapshot.needle * width))
                    }
                }
            }
            .frame(width: width, height: live ? 36 : 18)
        }
        .frame(height: live ? 36 : 18)
        .accessibilityHidden(true)
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
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(buttonFill)
            Text("開通")
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(Color.white.opacity(engine.snapshot.controlEnabled ? 0.92 : 0.35))
                .offset(x: engine.snapshot.jammed ? 6 : 0)
            ApproachClearTouchPad(
                enabled: engine.snapshot.controlEnabled && !interactionsFrozen,
                onDown: { handleDown() },
                onUp: { handleUp() },
                onCancel: { engine.touchCancel() }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
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
        engine.snapshot.accent == .hot || engine.snapshot.accent == .blaze ? Ink.gold : Ink.cyan
    }

    private var flashColor: Color {
        switch engine.snapshot.flash {
        case .none: Ink.edge
        case .perfect: Ink.gold
        case .good: Ink.green
        case .miss: Ink.red
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
        haptics.play(engine.touchDown(at: Self.milliseconds()))
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
