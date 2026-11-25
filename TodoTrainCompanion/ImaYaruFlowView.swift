import AppKit
import SwiftUI
import TodoTrainSync
import TodoTrainTicketUI

/// Frameless f20 machine, centered on the screen that holds the pointer. Confirm and wait stay with the snap.
struct ImaYaruFormView: View {
    @Environment(CompanionMacRuntime.self) private var runtime

    var initialNotice: String?
    var seededTitle: String = ""
    var seededMinutes: Int = 30
    var seededPrior: UUID?
    var anchor: CGPoint
    var stageSize: CGSize
    var ticketSize: CGSize
    var menuAnchor: CGPoint
    var scrollBridge: ImaYaruScrollBridge
    var focusBridge: ImaYaruFocusBridge
    var onDispense: (_ title: String, _ minutes: Int, _ priorSessionId: UUID?) -> Void
    var onClose: () -> Void

    @State private var title = ""
    @State private var minutes = 30
    @State private var phase: FormPhase = .editing
    @State private var notice: String?
    @State private var sendID = 0
    @State private var sentTitle = ""
    @State private var sentMinutes = 30
    @State private var sentPrior: UUID?
    @State private var arm: ImaYaruArm = .none
    @State private var departCharge: CGFloat = 0
    @State private var saveCharge: CGFloat = 0
    @State private var lamp: CGFloat = 0.35
    @State private var shake: CGFloat = 0
    @State private var slotOn = true
    @State private var flight: Flight?
    @State private var flightFrame: ImaYaruFlightFrame?
    @State private var departReady = false
    @State private var flightDone = false
    @State private var reduceMotion = false
    @State private var strokeX: CGFloat = 0
    @State private var strokeY: CGFloat = 0
    @State private var strokeAxis: ImaYaruStrokeAxis?
    @State private var strokeAnchor = 30
    @State private var catapultPhase: Double = 0
    @State private var follow = CGSize.zero
    @State private var tilt: Double = 0
    @State private var lastPointer = CGSize.zero
    @State private var lastPointerTime = Date()
    @FocusState private var titleFocused: Bool

    private enum FormPhase {
        case editing
        case sending
    }

    private struct Flight {
        enum Kind { case depart, save }
        var kind: Kind
        var started: Date
        var geometry: ImaYaruFlightGeometry
        var title: String
        var minutes: Int
    }

    /// Reference height for a two-finger stroke, in the same points as scrolling deltas.
    private static let strokePadHeight: CGFloat = 160

    private var trimmedTitle: String {
        IssueAndBoardEvaluating.trimmedTitle(title)
    }

    private var canIssue: Bool {
        IssueAndBoardEvaluating.isValid(title: trimmedTitle, estimatedSeconds: minutes * 60)
    }

    private var gate: ImaYaruDepartGate {
        ImaYaruDepartGate.resolve(
            serviceActive: runtime.snap?.serviceActive == true,
            timetableRide: ImaYaruOffer.isTimetableRide(runtime.snap)
        )
    }

    private var canDepart: Bool {
        canIssue && gate.departEnabled
    }

    var body: some View {
        let focusToken = focusBridge.token
        return ImaYaruStageView(
            title: $title,
            picture: picture,
            interactive: phase == .editing && flight == nil,
            titleFocused: $titleFocused,
            onSubmitTitle: submitTitle,
            onMachineDrag: { translation, ended in
                pointer(translation, ended: ended)
            },
            onBackgroundDrag: { translation, ended in
                pointer(translation, ended: ended)
            }
        )
        .task {
            while !Task.isCancelled {
                tick(Date())
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        .onAppear {
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if title.isEmpty {
                minutes = EstimateSnapMapping.snap(rawMinutes: Double(seededMinutes))
                if !seededTitle.isEmpty {
                    title = seededTitle
                    sentTitle = seededTitle
                    sentMinutes = minutes
                    sentPrior = seededPrior
                }
            }
            if notice == nil {
                notice = initialNotice
            }
            focusTitle()
            scrollBridge.onScroll = { dx, dy, phase in
                ingestScroll(dx: dx, dy: dy, phase: phase)
            }
            noteProgress()
        }
        .onDisappear {
            scrollBridge.onScroll = nil
        }
        .onChange(of: runtime.issueBoardTrack) { _, _ in
            noteProgress()
        }
        .onChange(of: runtime.snap) { _, _ in
            noteProgress()
        }
        .onChange(of: focusToken) { _, _ in
            focusTitle()
        }
        .onChange(of: runtime.issueOnlyFailure) { _, failure in
            guard let failure else { return }
            if flight?.kind == .save {
                abortSave(notice: failure)
                return
            }
            guard phase == .editing, flight == nil else { return }
            notice = failure
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        .onExitCommand(perform: onClose)
        .onKeyPress(.leftArrow) {
            guard phase == .editing, flight == nil, !titleFocused else { return .ignored }
            if canIssue {
                setArm(.save, departCharge: 0, saveCharge: 1)
            } else {
                setArm(.blocked, departCharge: 0, saveCharge: 0)
                shake = 1
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard phase == .editing, flight == nil, !titleFocused else { return .ignored }
            if canDepart {
                setArm(.depart, departCharge: 1, saveCharge: 0)
            } else {
                setArm(.blocked, departCharge: 0, saveCharge: 0)
                shake = 1
            }
            return .handled
        }
        .background {
            Button(action: commandReturn) { EmptyView() }
                .keyboardShortcut(.return, modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task(id: sendID) {
            guard phase == .sending else { return }
            try? await Task.sleep(for: .seconds(ImaYaruWait.captionAfter))
            guard phase == .sending else { return }
            notice = SyncCopy.waitingForIPhone
            let rest = ImaYaruWait.limit - ImaYaruWait.captionAfter
            try? await Task.sleep(for: .seconds(rest))
            guard phase == .sending else { return }
            runtime.suppressRideOverlay = false
            phase = .editing
            flight = nil
            flightFrame = nil
            flightDone = false
            departReady = false
            notice = SyncCopy.iphoneNoReply
        }
    }

    private var picture: ImaYaruStagePicture {
        let shift = reduceMotion ? 0 : (flightFrame?.machineShift ?? 0)
        let center = CGPoint(x: anchor.x + shift, y: anchor.y)
        let flying = flight != nil
        let direction = flight?.geometry.direction ?? aimDirection
        let mouth = mouthX(direction: direction == 0 ? 1 : direction, shift: shift)
        let showTicket = flying || arm == .depart || arm == .save
        let ticketCenter: CGPoint
        let reveal: CGFloat
        if let frame = flightFrame, flying {
            if reduceMotion {
                ticketCenter = flight?.geometry.origin ?? center
                reveal = frame.printReveal
            } else {
                ticketCenter = frame.ticketCenter
                reveal = frame.printReveal
            }
        } else {
            let tucked = tuckedOrigin(direction: direction == 0 ? 1 : direction)
            ticketCenter = CGPoint(x: tucked.x + follow.width, y: tucked.y + follow.height)
            reveal = 0
        }
        return ImaYaruStagePicture(
            ticketTitle: flying ? (flight?.title ?? title) : title,
            minutes: flying ? (flight?.minutes ?? minutes) : minutes,
            gate: gate,
            needsTitle: !canIssue && flight == nil,
            arm: arm,
            departCharge: departCharge,
            saveCharge: saveCharge,
            lamp: lamp,
            slotOn: flightFrame?.slotOn ?? slotOn,
            shake: reduceMotion ? 0 : shake,
            ticketSize: ticketSize,
            showTicket: showTicket && direction != 0,
            ticketCenter: ticketCenter,
            printReveal: reveal,
            tilt: flying || reduceMotion ? 0 : tilt,
            machineCenter: center,
            mouthX: mouth,
            flightDirection: showTicket ? (direction == 0 ? 1 : direction) : 0,
            catapult: catapult(mouthIsLive: canDepart),
            notice: notice,
            reduceMotion: reduceMotion,
            stageSize: stageSize,
            machineOpacity: reduceMotion ? 1 : (flightFrame?.machineOpacity ?? 1)
        )
    }

    private var aimDirection: CGFloat {
        switch arm {
        case .depart: 1
        case .save: -1
        case .blocked, .none: 0
        }
    }

    private func catapult(mouthIsLive: Bool) -> ImaYaruCatapultPicture? {
        guard mouthIsLive else { return nil }
        let launching = flight?.kind == .depart
        let charging = arm == .depart || departCharge > 0.04
        guard launching || charging else { return nil }
        let mouth = mouthX(direction: 1, shift: reduceMotion ? 0 : (flightFrame?.machineShift ?? 0))
        let length = ImaYaruFlight.railLength(stageWidth: stageSize.width, mouthX: mouth)
        let frame = flightFrame
        return ImaYaruCatapultPicture(
            length: length,
            charge: launching ? 1 : max(departCharge, arm == .depart ? 1 : 0),
            retract: reduceMotion ? 0 : (frame?.catapultRetract ?? 0),
            phase: catapultPhase,
            armed: arm == .depart || launching,
            launching: launching && (frame?.stage ?? 0) >= 3,
            tip: lightTip(frame: frame, mouth: mouth, length: length)
        )
    }

    /// Depart light sits on the ticket's leading edge, as a fraction of the rail.
    private func lightTip(frame: ImaYaruFlightFrame?, mouth: CGFloat, length: CGFloat) -> CGFloat {
        guard let frame, frame.stage >= 3, length > 1 else { return 0 }
        let leading = frame.ticketCenter.x + ticketSize.width / 2
        return min(1, max(0, (leading - mouth) / length))
    }

    private func mouthX(direction: CGFloat, shift: CGFloat) -> CGFloat {
        let half = ImaYaruMachineMetrics.fitted(ticket: ticketSize).body.width / 2
        if direction < 0 {
            return anchor.x + shift - half
        }
        return anchor.x + shift + half
    }

    private func tuckedOrigin(direction: CGFloat) -> CGPoint {
        let mouth = mouthX(direction: direction, shift: 0)
        let x = direction < 0 ? mouth + ticketSize.width / 2 : mouth - ticketSize.width / 2
        return CGPoint(x: x, y: anchor.y)
    }

    private var rideConfirmed: Bool {
        guard phase == .sending else { return false }
        return ImaYaruSnap.confirms(
            snap: runtime.snap,
            title: sentTitle,
            priorSessionId: sentPrior
        )
    }

    private func submitTitle() {
        perform(ImaYaruRelease.keyboard(commandReturn: false, gate: gate, canIssue: canIssue))
    }

    private func commandReturn() {
        guard phase == .editing, flight == nil else { return }
        perform(ImaYaruRelease.keyboard(commandReturn: true, gate: gate, canIssue: canIssue))
    }

    private func pointer(_ translation: CGSize, ended: Bool) {
        guard phase == .editing, flight == nil else { return }
        let now = Date()
        let dt = max(0.001, now.timeIntervalSince(lastPointerTime))
        let velocity = (translation.width - lastPointer.width) / dt
        lastPointer = translation
        lastPointerTime = now
        let choice = ImaYaruSectorHit.choice(dx: translation.width, dy: translation.height)
        if !ended {
            followTarget(translation, velocityX: velocity)
            preview(choice)
            return
        }
        let action = ImaYaruRelease.resolve(choice: choice, gate: gate, canIssue: canIssue)
        follow = .zero
        tilt = 0
        perform(action)
    }

    private func followTarget(_ translation: CGSize, velocityX: CGFloat) {
        let limit = ImaYaruTicketMetrics.pt(12)
        let length = hypot(translation.width, translation.height)
        let scale = length > limit && length > 0 ? limit / length : 1
        let next = CGSize(width: translation.width * scale, height: translation.height * scale)
        if reduceMotion {
            follow = next
            tilt = 0
        } else {
            withAnimation(.spring(response: ImaYaruFollow.response, dampingFraction: ImaYaruFollow.damping)) {
                follow = next
            }
            tilt = ImaYaruFollow.tilt(velocityX: velocityX, reduceMotion: false)
        }
    }

    private func preview(_ choice: ImaYaruChoice) {
        switch choice {
        case .depart:
            if canDepart {
                setArm(.depart, departCharge: 1, saveCharge: 0)
            } else if arm != .blocked {
                setArm(.blocked, departCharge: 0, saveCharge: 0)
                shake = 1
            }
        case .save:
            if canIssue {
                setArm(.save, departCharge: 0, saveCharge: 1)
            } else if arm != .blocked {
                setArm(.blocked, departCharge: 0, saveCharge: 0)
                shake = 1
            }
        case .neutral, .click:
            if arm != .none {
                arm = .none
                departCharge = 0
                saveCharge = 0
                lamp = 0.35
            }
        }
    }

    private func ingestScroll(dx: CGFloat, dy: CGFloat, phase eventPhase: NSEvent.Phase) {
        guard phase == .editing, flight == nil else { return }
        if eventPhase.contains(.began) || eventPhase.contains(.mayBegin) {
            strokeX = 0
            strokeY = 0
            strokeAxis = nil
            strokeAnchor = minutes
            if arm != .none { clearAim() }
            return
        }
        if eventPhase.contains(.ended) || eventPhase.contains(.cancelled) {
            if strokeAxis == .horizontal {
                perform(ImaYaruRelease.resolve(arm: arm, gate: gate, canIssue: canIssue))
            } else if arm != .depart && arm != .save {
                departCharge = 0
                saveCharge = 0
            }
            strokeX = 0
            strokeY = 0
            strokeAxis = nil
            return
        }
        strokeX += dx
        strokeY += dy
        if strokeAxis == nil {
            strokeAxis = ImaYaruStrokeAxis.lock(dx: strokeX, dy: strokeY)
        }
        guard let strokeAxis else { return }
        switch strokeAxis {
        case .vertical:
            minutes = ImaYaruMinutesStroke.minutes(
                anchor: strokeAnchor,
                dy: strokeY,
                padHeight: Self.strokePadHeight
            )
        case .horizontal:
            let next = ImaYaruFlick.arm(
                dx: strokeX,
                dy: strokeY,
                current: arm,
                departEnabled: gate.departEnabled,
                canIssue: canIssue
            )
            let amount = ImaYaruFlick.charge(dx: strokeX, dy: strokeY)
            if strokeX >= 0 {
                setArm(next, departCharge: amount, saveCharge: 0)
            } else {
                setArm(next, departCharge: 0, saveCharge: amount)
            }
            if next == .blocked {
                shake = max(shake, 0.65)
            }
        }
    }

    private func setArm(_ next: ImaYaruArm, departCharge: CGFloat, saveCharge: CGFloat) {
        if next != arm {
            switch next {
            case .depart, .save:
                ImaYaruHaptics.alignment()
                withAnimation(.easeOut(duration: ImaYaruFlight.lightSeconds)) {
                    lamp = 1
                }
            case .blocked:
                shake = 1
                lamp = 0.28
            case .none:
                lamp = 0.35
            }
            arm = next
        }
        self.departCharge = departCharge
        self.saveCharge = saveCharge
    }

    private func perform(_ action: ImaYaruReleaseAction) {
        switch action {
        case .close:
            onClose()
        case .none:
            clearAim()
        case .deny:
            shake = 1
            clearAim()
        case .save:
            issueOnly()
        case .depart:
            depart()
        }
    }

    private func clearAim() {
        arm = .none
        departCharge = 0
        saveCharge = 0
        lamp = 0.35
        follow = .zero
        tilt = 0
    }

    private func issueOnly() {
        guard phase == .editing, flight == nil, canIssue else { return }
        let trimmed = trimmedTitle
        let issuedMinutes = minutes
        let seconds = issuedMinutes * 60
        notice = nil
        beginFlight(.save, title: trimmed, minutes: issuedMinutes)
        Task { await runtime.sendIssue(title: trimmed, estimatedSeconds: seconds) }
    }

    private func depart() {
        guard phase == .editing, flight == nil, canDepart else { return }
        let trimmed = trimmedTitle
        sentTitle = trimmed
        sentMinutes = minutes
        sentPrior = ImaYaruOffer.ridingSessionID(runtime.snap)
        notice = SyncCopy.sentToIPhone
        phase = .sending
        departReady = false
        flightDone = false
        runtime.suppressRideOverlay = true
        sendID += 1
        beginFlight(.depart, title: trimmed, minutes: minutes)
        let seconds = minutes * 60
        Task { await runtime.sendIssueAndBoard(title: trimmed, estimatedSeconds: seconds) }
    }

    private func beginFlight(_ kind: Flight.Kind, title: String, minutes: Int) {
        ImaYaruHaptics.levelChange()
        let direction: CGFloat = kind == .depart ? 1 : -1
        let origin = tuckedOrigin(direction: direction)
        let destination: CGPoint
        let edge = ImaYaruTicketMetrics.pt(16)
        if kind == .depart {
            destination = CGPoint(x: stageSize.width + ticketSize.width / 2 + edge, y: anchor.y)
        } else {
            destination = CGPoint(x: menuAnchor.x, y: -ticketSize.height / 2 - ImaYaruTicketMetrics.pt(6))
        }
        let half = ImaYaruMachineMetrics.fitted(ticket: ticketSize).body.width / 2
        let clearance: CGFloat
        if direction > 0 {
            clearance = anchor.x + half + edge
        } else {
            clearance = stageSize.width - (anchor.x - half) + edge
        }
        let geometry = ImaYaruFlightGeometry(
            ticketSize: ticketSize,
            origin: origin,
            destination: destination,
            machineClearance: max(clearance, ticketSize.width + ImaYaruTicketMetrics.pt(40)),
            direction: direction
        )
        arm = kind == .depart ? .depart : .save
        lamp = 1
        flightFrame = ImaYaruFlight.frame(tauMs: 0, geometry: geometry)
        flight = Flight(kind: kind, started: Date(), geometry: geometry, title: title, minutes: minutes)
    }

    private func tick(_ now: Date) {
        if shake > 0 {
            shake = max(0, shake - 1.0 / 30.0 / 0.26)
        }
        let hot = max(departCharge, saveCharge)
        if hot > 0.04 || arm == .depart || flight?.kind == .depart {
            let unit = min(1, max(0, (Double(hot) - 0.1) / 0.75))
            let omega = 0.9 + 3.1 * unit * unit * (3 - 2 * unit)
            catapultPhase += omega / 30
        }
        guard let flight else { return }
        let tau = now.timeIntervalSince(flight.started) * 1000
        let frame = ImaYaruFlight.frame(tauMs: tau, geometry: flight.geometry)
        flightFrame = frame
        if frame.finished, !flightDone {
            flightDone = true
            if flight.kind == .save {
                finishSaveFlight()
            } else {
                finishDepartIfReady()
            }
        }
    }

    /// Title field, once the panel is key. Present re-applies this on the next turn.
    private func focusTitle() {
        guard phase == .editing, flight == nil else { return }
        let focused = $titleFocused
        focused.wrappedValue = false
        DispatchQueue.main.async {
            focused.wrappedValue = true
            DispatchQueue.main.async {
                guard let window = NSApp.keyWindow as? ImaYaruFormPanel else { return }
                guard let field = ImaYaruFocus.editableField(in: window.contentView) else { return }
                window.makeFirstResponder(field)
            }
        }
    }

    private func finishSaveFlight() {
        if ImaYaruDismissal.closeAfterSaveFlight(failure: runtime.issueOnlyFailure) {
            onClose()
        } else if let failure = runtime.issueOnlyFailure {
            abortSave(notice: failure)
        }
    }

    private func abortSave(notice failure: String) {
        flight = nil
        flightFrame = nil
        flightDone = false
        clearAim()
        notice = failure
        focusTitle()
    }

    private func noteProgress() {
        guard phase == .sending else {
            if notice == SyncCopy.iphoneNoReply, snapMatchesSent {
                notice = nil
                onClose()
            }
            return
        }
        switch ImaYaruCommit.next(track: runtime.issueBoardTrack, rideConfirmed: rideConfirmed) {
        case .wait:
            break
        case .dispense:
            departReady = true
            finishDepartIfReady()
        case .fail(let error):
            runtime.suppressRideOverlay = false
            phase = .editing
            flight = nil
            flightFrame = nil
            flightDone = false
            departReady = false
            clearAim()
            notice = MenuBarPresentation.failureCopy(error)
        }
    }

    private func finishDepartIfReady() {
        guard phase == .sending, departReady, flightDone else { return }
        onDispense(sentTitle, sentMinutes, sentPrior)
    }

    private var snapMatchesSent: Bool {
        ImaYaruSnap.confirms(snap: runtime.snap, title: sentTitle, priorSessionId: sentPrior)
    }
}

enum ImaYaruHaptics {
    static func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func levelChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
