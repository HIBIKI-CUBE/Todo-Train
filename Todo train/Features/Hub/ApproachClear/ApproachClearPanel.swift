//
//  ApproachClearPanel.swift
//  Todo train
//
//  Shown only after a long absence. One play, then it goes away.
//  Lamps stay flat fills. The pass across the track is the glow. Signal
//  colors stay on the real service strip. The needle is a layer on the
//  display link. Judgement is the press, not the release.
//

import SwiftUI
import UIKit

struct ApproachClearPanel: View {
    var world: ApproachClearWorld
    var interactionsFrozen: Bool
    var onPlayStarted: () -> Void = {}
    var onFinished: () -> Void = {}

    @State private var runtime = ApproachClearRuntime()
    @State private var chrome = ApproachClearChrome()
    @State private var expanded = false
    @State private var haptics = ApproachClearHaptics()
    @State private var finished = false
    @State private var latencyNote = ""

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
        .modifier(ClearanceShake(active: chrome.shake || chrome.jammed))
        .animation(TrainTheme.Motion.soft, value: expanded)
        .animation(.easeOut(duration: 0.06), value: chrome.flash)
        .allowsHitTesting(!interactionsFrozen)
        .onChange(of: world) { _, newWorld in
            runtime.engine.world = newWorld
            step()
        }
        .onChange(of: interactionsFrozen) { _, frozen in
            let now = Self.milliseconds()
            if frozen {
                runtime.engine.freeze(at: now)
                haptics.stop()
            } else {
                runtime.engine.thaw(at: now)
            }
            publishIfNeeded()
        }
        .onChange(of: chrome.calm) { _, calm in
            if calm != nil { finish() }
        }
        .onDisappear { haptics.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("接近クリアランス")
    }

    private var collapsedBody: some View {
        Button {
            guard !finished else { return }
            haptics.prepare()
            withAnimation(TrainTheme.Motion.soft) {
                expanded = true
            }
        } label: {
            Capsule()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 18)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(finished)
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
                    finish()
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
                ApproachClearTrackHost(runtime: runtime, active: ticking) { now in
                    step(at: now)
                }
                .frame(height: 48)
                if chrome.phase == .interlock {
                    interlockDots
                }
                if chrome.barrierOn {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 52)

            Text(chrome.label)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                .accessibilityHidden(chrome.label.isEmpty)

            clearanceButton

            sessionBar

            #if DEBUG
            Text(chrome.debugLine)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !latencyNote.isEmpty {
                Text(latencyNote)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #endif
        }
    }

    private var ticking: Bool {
        expanded
            && !finished
            && !interactionsFrozen
            && chrome.phase != .dormant
            && chrome.phase != .calm
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
        let lamps = chrome.lamps
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
                    .fill(index < chrome.pipsLit ? TrainTheme.rail : Color(uiColor: .quaternarySystemFill))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private var interlockDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<ApproachClearTuning.interlockLamps, id: \.self) { index in
                let lit = index < chrome.interlockLit
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
        ApproachClearTouchPad(
            enabled: chrome.controlEnabled && !interactionsFrozen,
            sunk: chrome.contactDown,
            fill: plateFill,
            titleColor: chrome.controlEnabled ? .label : .secondaryLabel,
            onDown: { handleDown(at: $0) },
            onUp: { handleUp(at: $0) },
            onCancel: {
                runtime.engine.touchCancel()
                publishIfNeeded()
            }
        )
        .opacity(chrome.controlEnabled ? 1 : 0.45)
    }

    private var sessionBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color(uiColor: .quaternarySystemFill))
            Capsule()
                .fill(accentColor.opacity(0.85))
                .frame(width: max(0, geo.size.width * (Double(chrome.sessionBucket) / 240)))
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
        switch chrome.flash {
        case .perfect, .good: TrainTheme.rail
        case .miss: Color.primary.opacity(0.45)
        case .none: TrainTheme.track
        }
    }

    private var labelColor: Color {
        switch chrome.label {
        case "良", "可": TrainTheme.rail
        case "早", "遅", "見送り": Color.primary
        default: Color.secondary
        }
    }

    private var plateFill: UIColor {
        switch chrome.armed {
        case .perfect, .good:
            (UIColor(named: "AccentColor") ?? .tintColor).withAlphaComponent(chrome.contactDown ? 0.22 : 0.14)
        case .none:
            .tertiarySystemGroupedBackground
        }
    }

    private func handleDown(at touchMs: Double) {
        runtime.engine.world = world
        let before = runtime.engine.snapshot
        let judgedMs = ApproachClearLatency.judgementMs(
            touchMs: touchMs,
            inputLatencyMs: runtime.latency.latencyMs
        )
        let wasDormant = before.phase == .dormant
        let cues = runtime.engine.touchDown(at: judgedMs)
        if wasDormant, runtime.engine.snapshot.phase != .dormant {
            onPlayStarted()
        }
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
            runtime.sweepStartMs = touchMs
            runtime.sweepPerfect = perfect
        }
        noteLatency(before: before, touchMs: touchMs)
        haptics.play(cues)
        publishIfNeeded()
    }

    /// Samples the raw touch-to-frame gap. The press itself already used the stored latency.
    private func noteLatency(before: ApproachClearSnapshot, touchMs: Double) {
        guard before.phase == .approach,
              runtime.engine.snapshot.phase == .resolved,
              runtime.engine.snapshot.pressU != nil,
              before.bands.approachMs > 0
        else { return }
        let presentation = runtime.lastPresentationMs
        guard presentation > 0 else { return }
        let approachMs = before.bands.approachMs
        let rawU = (touchMs - before.approachStart) / approachMs
        let visibleU = (presentation - before.approachStart) / approachMs
        let rawDelta = ApproachClearLatency.deltaMs(
            pressU: rawU,
            visibleNeedleU: visibleU,
            approachMs: approachMs
        )
        runtime.latency.record(rawDeltaMs: rawDelta)
        ApproachClearLatencyStore.save(runtime.latency)
        #if DEBUG
        let pressU = runtime.engine.snapshot.pressU ?? 0
        let visibleDrawn = ApproachClearTrackUIView.needleUnit(presentationMs: presentation, snap: before)
        let residual = ApproachClearLatency.deltaMs(
            pressU: pressU,
            visibleNeedleU: visibleDrawn,
            approachMs: approachMs
        )
        latencyNote = String(
            format: "pressU=%.3f visibleNeedleU=%.3f deltaMs=%.1f latencyMs=%.1f",
            pressU,
            visibleDrawn,
            residual,
            runtime.latency.latencyMs
        )
        print("approachClear \(latencyNote)")
        #endif
    }

    private func handleUp(at milliseconds: Double) {
        runtime.engine.world = world
        haptics.play(runtime.engine.touchUp(at: milliseconds))
        publishIfNeeded()
    }

    private func step(at now: Double = Self.milliseconds()) {
        guard ticking else { return }
        let previous = runtime.engine.snapshot
        runtime.engine.world = world
        let cues = runtime.engine.tick(at: now)
        let next = runtime.engine.snapshot
        if next.phase == .idle && previous.phase != .idle
            || next.phase == .approach && previous.phase != .approach {
            haptics.prepare()
        }
        if previous.bands != next.bands, previous.bands.goodR > previous.bands.goodL {
            runtime.ghostGoodL = previous.bands.goodL
            runtime.ghostGoodR = previous.bands.goodR
            runtime.ghostUntilMs = now + 400
        }
        if next.barrierOn, !previous.barrierOn {
            runtime.barrierStartMs = now
        }
        haptics.play(cues)
        publishIfNeeded()
    }

    private func publishIfNeeded() {
        let next = ApproachClearChrome(runtime.engine.snapshot)
        if next != chrome {
            chrome = next
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        haptics.stop()
        withAnimation(TrainTheme.Motion.soft) {
            expanded = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            onFinished()
        }
    }

    private static func milliseconds() -> Double {
        CACurrentMediaTime() * 1_000
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
    var sunk: Bool
    var fill: UIColor
    var titleColor: UIColor
    var onDown: (Double) -> Void
    var onUp: (Double) -> Void
    var onCancel: () -> Void

    func makeUIView(context: Context) -> ApproachClearTouchView {
        let view = ApproachClearTouchView()
        view.onDown = onDown
        view.onUp = onUp
        view.onCancel = onCancel
        view.apply(enabled: enabled, sunk: sunk, fill: fill, titleColor: titleColor)
        return view
    }

    func updateUIView(_ uiView: ApproachClearTouchView, context: Context) {
        uiView.onDown = onDown
        uiView.onUp = onUp
        uiView.onCancel = onCancel
        uiView.apply(enabled: enabled, sunk: sunk, fill: fill, titleColor: titleColor)
    }
}

private final class ApproachClearTouchView: UIView {
    var onDown: (Double) -> Void = { _ in }
    var onUp: (Double) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private let well = UIView()
    private let plate = UIView()
    private let title = UILabel()
    private var tracked: UITouch?
    private var sunk = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "開通"
        accessibilityTraits = .button

        well.backgroundColor = .tertiarySystemFill
        well.isUserInteractionEnabled = false
        plate.isUserInteractionEnabled = false
        plate.layer.cornerRadius = TrainTheme.Radius.control
        plate.layer.borderWidth = 1
        well.layer.cornerRadius = TrainTheme.Radius.control
        let font = UIFont.preferredFont(forTextStyle: .title3)
        title.font = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        title.textAlignment = .center
        title.text = "開通"
        title.isUserInteractionEnabled = false
        addSubview(well)
        addSubview(plate)
        plate.addSubview(title)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _: UITraitCollection) in
            view.plate.layer.borderColor = UIColor.separator.resolvedColor(with: view.traitCollection).cgColor
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(enabled: Bool, sunk: Bool, fill: UIColor, titleColor: UIColor) {
        isUserInteractionEnabled = enabled
        plate.backgroundColor = fill
        title.textColor = titleColor
        plate.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        if tracked == nil {
            self.sunk = sunk
        }
        applySink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        well.frame = CGRect(x: 0, y: 4, width: width, height: 68)
        plate.frame = CGRect(x: 0, y: 0, width: width, height: 68)
        title.frame = plate.bounds
        applySink()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled, tracked == nil, let touch = touches.first else { return }
        tracked = touch
        let stamp = touch.timestamp * 1_000
        sunk = true
        applySink()
        onDown(stamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch === tracked else { return }
        tracked = nil
        sunk = false
        applySink()
        onUp(touch.timestamp * 1_000)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracked != nil else { return }
        tracked = nil
        sunk = false
        applySink()
        onCancel()
    }

    private func applySink() {
        let shift = CGAffineTransform(translationX: 0, y: sunk ? 4 : 0)
        plate.transform = shift
    }
}
