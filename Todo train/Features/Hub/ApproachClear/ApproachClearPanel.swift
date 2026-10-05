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

    @State private var engine = ApproachClearPanel.liveEngine()
    @State private var expanded = false
    @State private var haptics = ApproachClearHaptics()
    @State private var bandPulse = false
    @State private var sweepStartMs = 0.0
    @State private var sweepPerfect = false
    @State private var sweepTier = 0
    @State private var ghostGoodL = 0.0
    @State private var ghostGoodR = 0.0
    @State private var ghostUntilMs = 0.0
    @State private var barrierStartMs = 0.0
    /// When the next frame will appear. The needle is drawn for this instant.
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
            if let bloom = hitBloom {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(bloom)
                    .opacity(engine.snapshot.flash == .miss ? missBlink : 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if engine.snapshot.easing {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Ink.cyan.opacity(0.16), .clear],
                            center: UnitPoint(x: 0.5, y: 0.4),
                            startRadius: 4,
                            endRadius: 160
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: heatAura, radius: engine.snapshot.tier >= 2 ? 14 : 8)
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
                        .fill(Color.white.opacity(0.16))
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 52)

            shimmerRow

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
            ApproachClearDisplayLink(active: ticking) { presentation in
                presentationMs = presentation
                step()
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
        let lamps = engine.snapshot.lamps
        let row: [(String, Bool, Color)] = [
            ("接近", lamps.approach, Ink.cyan),
            ("良", lamps.perfect, Ink.gold),
            ("可", lamps.good, Ink.green),
            ("通", lamps.clear, Ink.green),
            ("否", lamps.reject, Ink.red),
            ("連", lamps.interlock, TrainTheme.signalAmber),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(row.enumerated()), id: \.offset) { index, lamp in
                toyLamp(lamp.0, on: lamp.1, color: lamp.2, index: index)
            }
        }
    }

    private func toyLamp(_ title: String, on: Bool, color: Color, index: Int) -> some View {
        let hot = cascadeHot(index)
        return VStack(spacing: 2) {
            Circle()
                .fill(on || hot ? color : Color.white.opacity(0.1))
                .frame(width: 7, height: 7)
                .scaleEffect(hot ? 1.45 : 1)
                .shadow(color: hot ? color.opacity(0.9) : .clear, radius: 4)
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.white.opacity(on || hot ? 0.7 : 0.28))
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
            let rejected = engine.snapshot.flash == .miss || engine.snapshot.needleRejected
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                if live {
                    flowMarks(width: width)
                }
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                if live {
                    if presentationMs < ghostUntilMs, ghostGoodR > ghostGoodL {
                        let fade = max(0, (ghostUntilMs - presentationMs) / 400)
                        window(
                            ghostGoodL,
                            ghostGoodR,
                            width: width,
                            fill: Color.white.opacity(0.02),
                            stroke: Ink.cyan.opacity(0.55 * fade),
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
                            fill: (rejected ? Ink.red : Ink.green).opacity((rejected ? 0.28 : 0.22) * breath),
                            stroke: (rejected ? Ink.red : Ink.green).opacity(rejected ? 0.9 : 0.55),
                            height: 36,
                            dashed: false
                        )
                        window(
                            bands.perfL,
                            bands.perfR,
                            width: width,
                            fill: (rejected ? Ink.red : Ink.gold).opacity(rejected ? 0.34 : 0.42),
                            stroke: (rejected ? Ink.red : Ink.gold).opacity(0.9),
                            height: 36,
                            dashed: false
                        )
                        Rectangle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 2, height: 44)
                            .shadow(color: .white.opacity(0.85), radius: 3)
                            .offset(x: bands.center * width - 1)
                    }
                    .animation(.timingCurve(0.3, 0, 0.2, 1, duration: 0.22), value: bands)
                    if let press = engine.snapshot.pressU {
                        Rectangle()
                            .fill(markColor)
                            .frame(width: 2, height: 46)
                            .shadow(color: markColor.opacity(0.9), radius: 4)
                            .offset(x: press * width - 1)
                    }
                    Group {
                        if engine.snapshot.needleVisible {
                            let needleU = shownNeedle
                            let x = needleU * width
                            if engine.snapshot.tier >= 2 {
                                Capsule()
                                    .fill(needleColor.opacity(engine.snapshot.accent == .blaze ? 0.7 : 0.4))
                                    .frame(width: max(18, width * 0.1), height: 4)
                                    .offset(x: max(0, x - width * 0.1))
                            }
                            if bands.doubleBlip {
                                Circle()
                                    .fill(needleColor.opacity(0.55))
                                    .frame(width: 7, height: 7)
                                    .shadow(color: needleColor.opacity(0.45), radius: 3)
                                    .offset(x: max(0, needleU - bands.ghostOffset) * width - 3.5)
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
                    }
                    .animation(nil, value: shownNeedle)
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

    private func flowMarks(width: CGFloat) -> some View {
        let period = engine.snapshot.tier >= 2 ? 700.0 : 1_400.0
        let shift = presentationMs > 0 ? (presentationMs / period).truncatingRemainder(dividingBy: 1) : 0
        let tint = engine.snapshot.tier >= 2 ? Ink.gold : Ink.cyan
        return ZStack(alignment: .leading) {
            ForEach(0..<8, id: \.self) { index in
                let place = (Double(index) / 8 + shift).truncatingRemainder(dividingBy: 1)
                Rectangle()
                    .fill(tint.opacity(engine.snapshot.tier >= 1 ? 0.16 : 0.06))
                    .frame(width: 2, height: 48)
                    .offset(x: place * width)
            }
        }
        .allowsHitTesting(false)
    }

    private func rushingLight(width: CGFloat, progress: Double) -> some View {
        let travel = 0.06 + 0.78 * (1 - pow(1 - min(1, progress), 2.4))
        let fade = progress < 0.55 ? 1.0 : max(0, 1 - (progress - 0.55) / 0.45)
        let color = sweepTier >= 3 ? Ink.gold : (sweepPerfect ? Ink.gold : Ink.green)
        let trail: CGFloat = sweepTier >= 3 ? 128 : (sweepTier >= 2 ? 92 : 64)
        let head = travel * width
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, color.opacity(0.05), color.opacity(0.55), .white.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: trail, height: sweepTier >= 3 ? 10 : 6)
                .offset(x: head - trail + 30)
            UnevenRoundedRectangle(
                topLeadingRadius: 2,
                bottomLeadingRadius: 2,
                bottomTrailingRadius: 5,
                topTrailingRadius: 5
            )
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.35), .white],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 36, height: 12)
            .shadow(color: color.opacity(0.9), radius: sweepTier >= 2 ? 8 : 5)
            .offset(x: head)
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
                .shadow(color: color, radius: 5)
                .offset(x: head + 26)
        }
        .opacity(fade)
        .allowsHitTesting(false)
    }

    private func barrierFlash(width: CGFloat) -> some View {
        let elapsed = presentationMs - barrierStartMs
        let t = elapsed / 220
        return Group {
            if barrierStartMs > 0, t >= 0, t < 1 {
                LinearGradient(
                    colors: [.clear, TrainTheme.signalAmber.opacity(0.15), TrainTheme.signalAmber.opacity(0.7), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width * 0.42, height: 48)
                .offset(x: (t * 1.35 - 0.35) * width)
                .opacity(t < 0.25 ? t / 0.25 : 1 - t)
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
            .shadow(color: stroke.opacity(dashed ? 0 : 0.45), radius: 4)
            .offset(x: start * width)
    }

    private var shimmerRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { index in
                let on = shimmerOn(index)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(on ? shimmerColor : Color.white.opacity(0.08))
                    .frame(width: 6, height: on && sweepTier >= 2 ? 8 : 6)
                    .shadow(color: on ? shimmerColor.opacity(0.8) : .clear, radius: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var interlockDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<ApproachClearTuning.interlockLamps, id: \.self) { index in
                let lit = index < engine.snapshot.interlockLit
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(lit ? TrainTheme.signalAmber : Color.white.opacity(0.16))
                    .frame(width: 8, height: lit ? 14 : 8)
                    .shadow(color: lit ? TrainTheme.signalAmber.opacity(0.8) : .clear, radius: 4)
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
        switch displayedArm {
        case .perfect: Ink.gold.opacity(0.7)
        case .good: Ink.green.opacity(0.5)
        case .none: .clear
        }
    }

    private var armedRadius: CGFloat {
        switch displayedArm {
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
        switch displayedArm {
        case .perfect: Ink.gold.opacity(0.28)
        case .good: Ink.green.opacity(0.22)
        case .none: Color.white.opacity(engine.snapshot.contactDown ? 0.1 : 0.05)
        }
    }

    private var hitBloom: RadialGradient? {
        switch engine.snapshot.flash {
        case .perfect:
            RadialGradient(
                colors: [Ink.gold.opacity(0.42), Ink.gold.opacity(0.08), .clear],
                center: .center,
                startRadius: 6,
                endRadius: 180
            )
        case .good:
            RadialGradient(
                colors: [Ink.green.opacity(0.32), Ink.green.opacity(0.06), .clear],
                center: .center,
                startRadius: 6,
                endRadius: 170
            )
        case .miss:
            RadialGradient(
                colors: [Ink.red.opacity(0.5), Ink.red.opacity(0.12), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 180
            )
        case .none:
            nil
        }
    }

    private var missBlink: Double {
        guard presentationMs > 0 else { return 1 }
        let phase = (presentationMs / 46).truncatingRemainder(dividingBy: 1)
        return phase < 0.42 ? 1 : 0.16
    }

    private var heatAura: Color {
        switch engine.snapshot.flash {
        case .perfect: return Ink.gold.opacity(0.55)
        case .good: return Ink.green.opacity(0.4)
        case .miss: return Ink.red.opacity(0.45)
        case .none: break
        }
        switch engine.snapshot.accent {
        case .blaze: return Ink.gold.opacity(0.45)
        case .hot: return Ink.gold.opacity(0.22)
        case .warm: return Ink.cyan.opacity(0.18)
        case .cyan: return .clear
        }
    }

    private var sweepProgress: Double? {
        guard sweepStartMs > 0, presentationMs >= sweepStartMs else { return nil }
        let elapsed = presentationMs - sweepStartMs
        guard elapsed < 300 else { return nil }
        return elapsed / 280
    }

    private var shimmerColor: Color {
        sweepTier >= 3 || sweepPerfect ? Ink.gold : Ink.green
    }

    private func shimmerOn(_ index: Int) -> Bool {
        guard sweepStartMs > 0, presentationMs >= sweepStartMs else { return false }
        let elapsed = presentationMs - sweepStartMs
        guard elapsed < 520 else { return false }
        let count = (sweepPerfect || sweepTier >= 2) ? 12 : max(4, Int((12 * (0.55 + Double(sweepTier) * 0.2)).rounded()))
        guard index < count else { return false }
        let step = sweepPerfect ? 14.0 : 18.0
        let clearAt = Double(count - 1) * step + (sweepPerfect ? 140 : 90)
        if elapsed >= Double(index) * step, elapsed < clearAt { return true }
        if sweepTier >= 2 {
            let on = 190 + Double(11 - index) * 10
            if elapsed >= on, elapsed < 190 + 110 + 110 { return true }
        }
        return false
    }

    private func cascadeHot(_ index: Int) -> Bool {
        guard sweepTier >= 1, sweepStartMs > 0, presentationMs >= sweepStartMs else { return false }
        let elapsed = presentationMs - sweepStartMs
        guard elapsed < 520 else { return false }
        let step = sweepTier >= 3 ? 18.0 : 24.0
        let on = 30 + Double(index) * step
        if elapsed >= on, elapsed < on + 280 { return true }
        if sweepTier >= 2 {
            let back = 30 + Double(6 + (5 - index)) * step
            if elapsed >= back, elapsed < back + 280 { return true }
        }
        return false
    }

    /// Needle position at the upcoming frame. Logic keeps its own clock.
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
        var tier = 0
        var cleared = false
        for cue in cues {
            switch cue {
            case .perfect(let value):
                perfect = true
                tier = value
                cleared = true
            case .good(let value):
                tier = value
                cleared = true
            default:
                break
            }
        }
        if cleared {
            sweepStartMs = Self.milliseconds()
            sweepPerfect = perfect
            sweepTier = tier
        }
        haptics.prepare()
        haptics.play(cues)
    }

    private func handleUp(at milliseconds: Double) {
        engine.world = world
        haptics.play(engine.touchUp(at: milliseconds))
    }

    private func step() {
        guard ticking else { return }
        engine.world = world
        haptics.play(engine.tick(at: Self.milliseconds()))
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
        onFrame(link.targetTimestamp * 1_000)
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

private enum Ink {
    static let edge = Color.white.opacity(0.12)
    static let cyan = Color(red: 0.20, green: 0.88, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.90, blue: 0.40)
    static let green = Color(red: 0.24, green: 1.0, blue: 0.54)
    static let red = Color(red: 1.0, green: 0.23, blue: 0.23)
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
