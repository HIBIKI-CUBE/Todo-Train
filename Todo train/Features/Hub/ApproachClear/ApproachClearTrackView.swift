//
//  ApproachClearTrackView.swift
//  Todo train
//
//  The needle is a layer committed inside the display link, at
//  targetTimestamp — the time that commit is shown. Logic ticks at
//  CACurrentMediaTime. Judgement stays on UITouch.timestamp. All three
//  share the media clock. SwiftUI is not on this path: a state update
//  misses the frame, so the line the eye tracks is already late.
//

import SwiftUI
import UIKit

@MainActor
final class ApproachClearRuntime {
    var engine: ApproachClearEngine
    var sweepStartMs = 0.0
    var sweepPerfect = false
    var ghostGoodL = 0.0
    var ghostGoodR = 0.0
    var ghostUntilMs = 0.0
    var barrierStartMs = 0.0

    init() {
        var engine = ApproachClearEngine()
        engine.liveRandom = true
        self.engine = engine
    }

    func reset() {
        var engine = ApproachClearEngine()
        engine.liveRandom = true
        self.engine = engine
        sweepStartMs = 0
        sweepPerfect = false
        ghostGoodL = 0
        ghostGoodR = 0
        ghostUntilMs = 0
        barrierStartMs = 0
    }
}

struct ApproachClearChrome: Equatable {
    var phase: ApproachClearPhase = .dormant
    var lamps = ApproachClearLamps()
    var pipsLit = 0
    var label = ""
    var calm: ApproachClearCalm?
    var controlEnabled = true
    var contactDown = false
    var sessionBucket = 0
    var debugLine = ""
    var barrierOn = false
    var flash: ApproachClearFlash = .none
    var shake = false
    var jammed = false
    var interlockLit = 0
    var armed: ApproachClearArm = .none

    init() {}

    init(_ snapshot: ApproachClearSnapshot) {
        phase = snapshot.phase
        lamps = snapshot.lamps
        pipsLit = snapshot.pipsLit
        label = snapshot.label
        calm = snapshot.calm
        controlEnabled = snapshot.controlEnabled
        contactDown = snapshot.contactDown
        sessionBucket = Int((snapshot.sessionProgress * 240).rounded(.down))
        debugLine = snapshot.debug.line
        barrierOn = snapshot.barrierOn
        flash = snapshot.flash
        shake = snapshot.shake
        jammed = snapshot.jammed
        interlockLit = snapshot.interlockLit
        armed = snapshot.armed
    }
}

struct ApproachClearTrackHost: UIViewRepresentable {
    var runtime: ApproachClearRuntime
    var active: Bool
    var onLogic: (Double) -> Void

    func makeUIView(context: Context) -> ApproachClearTrackUIView {
        let view = ApproachClearTrackUIView()
        view.runtime = runtime
        view.onLogic = onLogic
        view.active = active
        return view
    }

    func updateUIView(_ uiView: ApproachClearTrackUIView, context: Context) {
        uiView.runtime = runtime
        uiView.onLogic = onLogic
        uiView.active = active
    }
}

final class ApproachClearTrackUIView: UIView {
    var runtime: ApproachClearRuntime?
    var onLogic: (Double) -> Void = { _ in }
    var active = false {
        didSet { syncLink() }
    }

    private var link: CADisplayLink?
    private var placedBands: ApproachClearBands?
    private var placedSize = CGSize.zero

    private let content = CALayer()
    private let track = CAShapeLayer()
    private let hairline = CALayer()
    private let goodWindow = CALayer()
    private let perfectWindow = CALayer()
    private let ghostWindow = CAShapeLayer()
    private let beat = CALayer()
    private let pressMark = CALayer()
    private let blip = CALayer()
    private let chevron = CAShapeLayer()
    private let needle = CALayer()
    private let needleDot = CALayer()
    private let flashStreak = CALayer()
    private let train = CALayer()
    private let tailWide = CALayer()
    private let tailTight = CALayer()
    private let carA = CALayer()
    private let carB = CALayer()
    private let carC = CALayer()
    private let barrier = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.addSublayer(content)
        content.addSublayer(track)
        content.addSublayer(hairline)
        content.addSublayer(goodWindow)
        content.addSublayer(perfectWindow)
        content.addSublayer(ghostWindow)
        content.addSublayer(beat)
        content.addSublayer(pressMark)
        content.addSublayer(flashStreak)
        content.addSublayer(train)
        train.addSublayer(tailWide)
        train.addSublayer(tailTight)
        train.addSublayer(carA)
        train.addSublayer(carB)
        train.addSublayer(carC)
        content.addSublayer(barrier)
        content.addSublayer(blip)
        content.addSublayer(needle)
        content.addSublayer(needleDot)
        content.addSublayer(chevron)

        goodWindow.cornerRadius = 3
        perfectWindow.cornerRadius = 3
        goodWindow.borderWidth = 1
        perfectWindow.borderWidth = 1
        ghostWindow.fillColor = nil
        ghostWindow.lineWidth = 1
        ghostWindow.lineDashPattern = [3, 2]
        beat.cornerRadius = 0.5
        pressMark.cornerRadius = 0.5
        blip.cornerRadius = 3.5
        needle.cornerRadius = 1
        needleDot.cornerRadius = 4
        flashStreak.cornerRadius = 5
        tailWide.cornerRadius = 2.5
        tailTight.cornerRadius = 1.5
        carA.cornerRadius = 1.5
        carB.cornerRadius = 1.5
        carC.cornerRadius = 2
        barrier.cornerRadius = 1.5
        chevron.path = Self.chevronPath
        chevron.bounds = CGRect(x: 0, y: 0, width: 8, height: 5)

        for item in [blip, chevron, needle, needleDot, pressMark, flashStreak, train, barrier, tailWide, tailTight, carA, carB, carC] {
            item.actions = [
                "position": NSNull(),
                "bounds": NSNull(),
                "opacity": NSNull(),
                "transform": NSNull(),
                "path": NSNull(),
                "shadowOpacity": NSNull(),
            ]
        }
        for item in [goodWindow, perfectWindow, beat, ghostWindow] {
            item.actions = [
                "opacity": NSNull(),
                "backgroundColor": NSNull(),
                "borderColor": NSNull(),
            ]
        }
        content.actions = ["transform": NSNull()]
        train.shadowOffset = .zero
        train.shadowRadius = 8
        flashStreak.shadowOffset = .zero
        flashStreak.shadowRadius = 7
        barrier.shadowOffset = .zero
        barrier.shadowRadius = 5
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _: UITraitCollection) in
            view.placedSize = .zero
            view.render(presentationMs: CACurrentMediaTime() * 1_000)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
        content.bounds = bounds
        content.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGPath(roundedRect: bounds, cornerWidth: bounds.height / 2, cornerHeight: bounds.height / 2, transform: nil)
        track.path = path
        hairline.frame = CGRect(x: 10, y: bounds.midY - 0.5, width: max(0, bounds.width - 20), height: 1)
        placedSize = .zero
        render(presentationMs: CACurrentMediaTime() * 1_000)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncLink()
    }

    @objc private func fire(_ link: CADisplayLink) {
        onLogic(CACurrentMediaTime() * 1_000)
        render(presentationMs: link.targetTimestamp * 1_000)
    }

    deinit {
        link?.invalidate()
    }

    private func render(presentationMs: Double) {
        guard let runtime, bounds.width > 1 else { return }
        let snap = runtime.engine.snapshot
        let rail = paint(UIColor(named: "AccentColor") ?? .tintColor)
        let rejected = snap.flash == .miss || snap.needleRejected
        let ink = paint(rejected ? .label : (UIColor(named: "AccentColor") ?? .tintColor))
        track.fillColor = paint(.tertiarySystemFill)
        hairline.backgroundColor = paint(.separator)

        let bandsChanged = placedBands != snap.bands
        let sizeChanged = placedSize != bounds.size
        if bandsChanged || sizeChanged {
            placeWindows(snap, ink: ink, borderAlpha: rejected ? 0.7 : 0.4, animate: bandsChanged && placedBands != nil)
            placedBands = snap.bands
            placedSize = bounds.size
        } else {
            paintWindows(ink, borderAlpha: rejected ? 0.7 : 0.4)
        }
        placeGhost(runtime, presentationMs: presentationMs)
        placeNeedle(snap, presentationMs: presentationMs, rail: rail)
        placePass(runtime, snap: snap, presentationMs: presentationMs, rail: rail)
        placeBarrier(runtime, presentationMs: presentationMs, rail: rail)
        let scale: CGFloat = snap.shrinking ? 0.92 : 1
        content.transform = CATransform3DMakeScale(scale, 1, 1)
    }

    private func syncLink() {
        let shouldRun = active && window != nil
        if shouldRun {
            guard link == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(fire(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            link?.invalidate()
            link = nil
        }
    }

    private func placeWindows(_ snap: ApproachClearSnapshot, ink: CGColor, borderAlpha: CGFloat, animate: Bool) {
        CATransaction.begin()
        if animate {
            CATransaction.setAnimationDuration(0.22)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1))
        } else {
            CATransaction.setDisableActions(true)
        }
        let bands = snap.bands
        goodWindow.frame = span(bands.goodL, bands.goodR, height: 36)
        perfectWindow.frame = span(bands.perfL, bands.perfR, height: 36)
        beat.frame = CGRect(
            x: bands.center * bounds.width - 0.5,
            y: (bounds.height - 44) / 2,
            width: 1,
            height: 44
        )
        paintWindows(ink, borderAlpha: borderAlpha)
        beat.backgroundColor = paint(UIColor.label.withAlphaComponent(0.85))
        CATransaction.commit()
    }

    private func paintWindows(_ ink: CGColor, borderAlpha: CGFloat) {
        let breath = breathAlpha
        goodWindow.backgroundColor = copy(ink, alpha: 0.16 * breath)
        goodWindow.borderColor = copy(ink, alpha: borderAlpha)
        perfectWindow.backgroundColor = copy(ink, alpha: 0.38)
        perfectWindow.borderColor = ink
        perfectWindow.isHidden = perfectWindow.bounds.width < 0.5
        goodWindow.isHidden = goodWindow.bounds.width < 0.5
    }

    private var breathAlpha: CGFloat {
        guard runtime?.engine.snapshot.idleBreath == true else { return 1 }
        let wave = 0.5 + 0.5 * sin(CACurrentMediaTime() * .pi * 2 / 1.8)
        return 0.62 + 0.38 * wave
    }

    private func placeGhost(_ runtime: ApproachClearRuntime, presentationMs: Double) {
        let remain = runtime.ghostUntilMs - presentationMs
        guard remain > 0, runtime.ghostGoodR > runtime.ghostGoodL else {
            ghostWindow.isHidden = true
            return
        }
        ghostWindow.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ghostWindow.frame = span(runtime.ghostGoodL, runtime.ghostGoodR, height: 40)
        ghostWindow.path = CGPath(roundedRect: ghostWindow.bounds, cornerWidth: 3, cornerHeight: 3, transform: nil)
        let fade = remain / 400
        ghostWindow.strokeColor = paint(UIColor.separator.withAlphaComponent(fade))
        ghostWindow.opacity = Float(fade)
        CATransaction.commit()
    }

    private func placeNeedle(_ snap: ApproachClearSnapshot, presentationMs: Double, rail: CGColor) {
        let show = snap.needleVisible
        needle.isHidden = !show
        needleDot.isHidden = !show
        chevron.isHidden = !show
        blip.isHidden = true
        guard show else {
            placePress(snap)
            return
        }
        let u = Self.needleUnit(presentationMs: presentationMs, snap: snap)
        let x = u * bounds.width
        let mark = snap.needleRejected ? paint(.label) : rail
        needle.backgroundColor = mark
        needle.frame = CGRect(x: x - 1, y: (bounds.height - 40) / 2, width: 2, height: 40)
        needleDot.backgroundColor = mark
        needleDot.frame = CGRect(x: x - 4, y: bounds.midY - 4, width: 8, height: 8)
        chevron.fillColor = mark
        chevron.position = CGPoint(x: x, y: bounds.midY - 18)
        if snap.bands.doubleBlip {
            blip.isHidden = false
            blip.backgroundColor = mark
            blip.opacity = 0.35
            let ghostX = max(0, u - snap.bands.ghostOffset) * bounds.width
            blip.frame = CGRect(x: ghostX - 3.5, y: bounds.midY - 3.5, width: 7, height: 7)
        }
        placePress(snap)
    }

    private func placePress(_ snap: ApproachClearSnapshot) {
        guard let press = snap.pressU else {
            pressMark.isHidden = true
            return
        }
        pressMark.isHidden = false
        let color: UIColor = switch snap.label {
        case "良", "可": UIColor(named: "AccentColor") ?? .tintColor
        default: .label
        }
        pressMark.backgroundColor = paint(color)
        pressMark.frame = CGRect(x: press * bounds.width - 0.5, y: (bounds.height - 46) / 2, width: 1, height: 46)
    }

    private func placePass(
        _ runtime: ApproachClearRuntime,
        snap: ApproachClearSnapshot,
        presentationMs: Double,
        rail: CGColor
    ) {
        let perfectFlash = snap.flash == .perfect
        let goodFlash = snap.flash == .good
        flashStreak.isHidden = !(perfectFlash || goodFlash)
        if perfectFlash || goodFlash {
            let height: CGFloat = perfectFlash ? 10 : 6
            flashStreak.frame = CGRect(x: 0, y: bounds.midY - height / 2, width: bounds.width, height: height)
            flashStreak.cornerRadius = height / 2
            flashStreak.backgroundColor = copy(rail, alpha: perfectFlash ? 0.34 : 0.2)
            flashStreak.shadowColor = rail
            flashStreak.shadowOpacity = perfectFlash ? 0.55 : 0.32
        }

        let elapsed = presentationMs - runtime.sweepStartMs
        guard runtime.sweepStartMs > 0, elapsed >= 0, elapsed < 380 else {
            train.isHidden = true
            return
        }
        train.isHidden = false
        let progress = elapsed / 280
        let travelT = min(1, progress)
        let travel = 0.02 + 0.90 * (1 - pow(1 - travelT, 2.4))
        let fade = travelT < 0.58 ? 1.0 : max(0, 1 - (progress - 0.58) / 0.78)
        let strength = runtime.sweepPerfect ? 1.0 : 0.72
        let head = travel * bounds.width
        train.frame = bounds
        train.opacity = Float(fade)
        tailWide.backgroundColor = copy(rail, alpha: 0.28 * strength)
        tailWide.frame = CGRect(x: head - 84, y: bounds.midY - 2.5, width: 92, height: 5)
        tailTight.backgroundColor = copy(rail, alpha: 0.8 * strength)
        tailTight.frame = CGRect(x: head - 34, y: bounds.midY - 1.5, width: 40, height: 3)
        let body = copy(rail, alpha: strength)
        carA.backgroundColor = body
        carB.backgroundColor = body
        carC.backgroundColor = body
        carA.frame = CGRect(x: head, y: bounds.midY - 3, width: 12, height: 6)
        carB.frame = CGRect(x: head + 14, y: bounds.midY - 3.5, width: 14, height: 7)
        carC.frame = CGRect(x: head + 30, y: bounds.midY - 4, width: 16, height: 8)
        train.shadowColor = rail
        train.shadowOpacity = Float(0.5 * strength)
    }

    private func placeBarrier(_ runtime: ApproachClearRuntime, presentationMs: Double, rail: CGColor) {
        let elapsed = presentationMs - runtime.barrierStartMs
        let t = elapsed / 220
        guard runtime.barrierStartMs > 0, t >= 0, t < 1 else {
            barrier.isHidden = true
            return
        }
        barrier.isHidden = false
        barrier.backgroundColor = rail
        barrier.shadowColor = rail
        barrier.shadowOpacity = 0.45
        let x = (t * 1.15 - 0.08) * bounds.width
        barrier.frame = CGRect(x: x, y: (bounds.height - 44) / 2, width: 5, height: 44)
        barrier.opacity = Float(t < 0.15 ? t / 0.15 : 1 - t)
    }

    private func span(_ start: Double, _ end: Double, height: CGFloat) -> CGRect {
        let width = max(0, (end - start) * bounds.width)
        return CGRect(x: start * bounds.width, y: (bounds.height - height) / 2, width: width, height: height)
    }

    private func paint(_ color: UIColor) -> CGColor {
        color.resolvedColor(with: traitCollection).cgColor
    }

    private func copy(_ color: CGColor, alpha: CGFloat) -> CGColor {
        UIColor(cgColor: color).withAlphaComponent(alpha).cgColor
    }

    private static let chevronPath: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 5))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        return path
    }()

    /// Where the needle is when this frame is on screen.
    static func needleUnit(presentationMs: Double, snap: ApproachClearSnapshot) -> Double {
        guard snap.phase == .approach, presentationMs > 0, snap.bands.approachMs > 0 else {
            return snap.needle
        }
        let u = (presentationMs - snap.approachStart) / snap.bands.approachMs
        return min(1, max(0, u))
    }
}
