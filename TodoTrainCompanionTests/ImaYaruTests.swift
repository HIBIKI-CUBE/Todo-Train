import AppKit
import Carbon
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import TodoTrainSync
import TodoTrainTicketUI
@testable import TodoTrainCompanion

struct ImaYaruTests {
    @Test func offerOpensWheneverPaired() {
        #expect(ImaYaruOffer.isAvailable(isPaired: true))
        #expect(!ImaYaruOffer.isAvailable(isPaired: false))
    }

    @Test func departNeedsServiceAndIsOffDuringATimetableRide() {
        #expect(ImaYaruOffer.canIssueAndBoard(serviceActive: true, timetableRide: false))
        #expect(!ImaYaruOffer.canIssueAndBoard(serviceActive: false, timetableRide: false))
        #expect(!ImaYaruOffer.canIssueAndBoard(serviceActive: true, timetableRide: true))
        #expect(ImaYaruOffer.isTimetableRide(nil) == false)

        let passenger = SnapPlaintext(
            rev: 1,
            sessionId: nil,
            ticketId: nil,
            title: nil,
            phase: .idle,
            startedAt: nil,
            estimatedSeconds: nil,
            pausedAccumulated: nil,
            pausedAt: nil,
            boardedDeviceID: nil,
            serviceActive: true,
            passengerAboard: true
        )
        #expect(ImaYaruOffer.isTimetableRide(passenger))
        #expect(!ImaYaruOffer.canIssueAndBoard(serviceActive: true, timetableRide: ImaYaruOffer.isTimetableRide(passenger)))

        let held = SnapPlaintext(
            rev: 2,
            sessionId: UUID(),
            ticketId: UUID(),
            title: "会議",
            phase: .paused,
            startedAt: 1,
            estimatedSeconds: 600,
            pausedAccumulated: 0,
            pausedAt: 2,
            boardedDeviceID: nil,
            serviceActive: true,
            pauseHeldBy: .passenger
        )
        #expect(ImaYaruOffer.isTimetableRide(held))

        let timetablePause = SnapPlaintext(
            rev: 3,
            sessionId: UUID(),
            ticketId: UUID(),
            title: "下書き",
            phase: .paused,
            startedAt: 1,
            estimatedSeconds: 600,
            pausedAccumulated: 0,
            pausedAt: 2,
            boardedDeviceID: nil,
            serviceActive: true,
            pauseHeldBy: .timetable
        )
        #expect(!ImaYaruOffer.isTimetableRide(timetablePause))
        #expect(ImaYaruOffer.canIssueAndBoard(serviceActive: true, timetableRide: ImaYaruOffer.isTimetableRide(timetablePause)))
    }

    @Test func idleSnapDoesNotNameARide() {
        let stale = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let idle = SnapPlaintext(
            rev: 1,
            sessionId: stale,
            ticketId: nil,
            title: nil,
            phase: .idle,
            startedAt: nil,
            estimatedSeconds: nil,
            pausedAccumulated: nil,
            pausedAt: nil,
            boardedDeviceID: nil,
            serviceActive: true
        )
        #expect(ImaYaruOffer.ridingSessionID(idle) == nil)
        #expect(ImaYaruOffer.ridingSessionID(nil) == nil)
        let riding = SnapPlaintext(
            rev: 2,
            sessionId: stale,
            ticketId: UUID(),
            title: "下書き",
            phase: .paused,
            startedAt: 1,
            estimatedSeconds: 600,
            pausedAccumulated: 0,
            pausedAt: 2,
            boardedDeviceID: "phone",
            serviceActive: true
        )
        #expect(ImaYaruOffer.ridingSessionID(riding) == stale)
    }

    @Test func snapConfirmsANewRideOnly() {
        let prior = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let fresh = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let snap = SnapPlaintext(
            rev: 2,
            sessionId: fresh,
            ticketId: UUID(),
            title: " 週次レビュー ",
            phase: .running,
            startedAt: 1,
            estimatedSeconds: 1500,
            pausedAccumulated: 0,
            pausedAt: nil,
            boardedDeviceID: "phone",
            serviceActive: true
        )
        #expect(ImaYaruSnap.confirms(snap: snap, title: " 週次レビュー ", priorSessionId: nil))
        #expect(ImaYaruSnap.confirms(snap: snap, title: "週次レビュー", priorSessionId: prior))
        #expect(!ImaYaruSnap.confirms(snap: snap, title: "週次レビュー", priorSessionId: fresh))
        #expect(!ImaYaruSnap.confirms(snap: nil, title: "週次レビュー", priorSessionId: nil))
    }

    @Test func ackFailureDoesNotBecomeARide() {
        let id = UUID()
        let sending = IssueBoardTracking.begin(
            cmdId: id,
            title: "下書き",
            priorSessionId: nil,
            current: .idle
        )
        let failed = IssueBoardTracking.applyAck(
            AckPlaintext(cmdId: id, ok: false, error: .invalidPayload),
            current: sending!
        )
        #expect(failed == .failed(.invalidPayload))
        let ok = IssueBoardTracking.applyAck(
            AckPlaintext(cmdId: id, ok: true),
            current: sending!
        )
        guard case .acked = ok else {
            Issue.record("expected ack")
            return
        }
    }

    @Test func confirmedRideDispensesEvenAfterAMismatchAck() {
        let id = UUID()
        #expect(ImaYaruCommit.next(track: .sending(cmdId: id, title: "下書き", priorSessionId: nil), rideConfirmed: false) == .wait)
        #expect(ImaYaruCommit.next(track: .acked(cmdId: id, title: "下書き", priorSessionId: nil), rideConfirmed: false) == .dispense)
        #expect(ImaYaruCommit.next(track: .failed(.sessionMismatch), rideConfirmed: false) == .fail(.sessionMismatch))
        #expect(ImaYaruCommit.next(track: .failed(.sessionMismatch), rideConfirmed: true) == .dispense)
    }

    @Test func waitCuesTimeout() {
        #expect(ImaYaruWait.cue(elapsed: 0) == .quiet)
        #expect(ImaYaruWait.cue(elapsed: 1.5) == .waiting)
        #expect(ImaYaruWait.cue(elapsed: 8) == .timedOut)
    }

    @Test func ticketEntersFromOffscreenAtThePip() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let pip = CGRect(x: 1440 - 12 - 320, y: 12, width: 320, height: 128)
        let rest = TicketDispenseGeometry.restingFrame(pip: pip)
        let entry = TicketDispenseGeometry.entryFrame(resting: rest, display: display)
        #expect(rest.midX == pip.midX)
        #expect(rest.midY == pip.midY)
        #expect(rest.width == pip.width)
        #expect(rest.height == MarsTicketSpec.height(forWidth: pip.width))
        #expect(rest.height > 100)
        #expect(entry.size == rest.size)
        #expect(entry.minY == rest.minY)
        #expect(entry.minX == display.maxX + TicketDispenseGeometry.edgeGap)

        let leftPip = CGRect(x: 12, y: 900 - 12 - 128, width: 320, height: 128)
        let leftRest = TicketDispenseGeometry.restingFrame(pip: leftPip)
        let leftEntry = TicketDispenseGeometry.entryFrame(resting: leftRest, display: display)
        #expect(leftEntry.minY == leftRest.minY)
        #expect(leftEntry.maxX < display.minX)
    }

    @Test func ticketRestsBeforeTheRideReplacesIt() {
        #expect(ImaYaruWait.ticketHold > 0)
        #expect(ImaYaruWait.ticketHold < ImaYaruWait.captionAfter)
    }

    @Test func shortcutNeedsAModifier() {
        #expect(ImaYaruShortcut.make(keyCode: 34, modifiers: [], characters: "i") == nil)
        #expect(ImaYaruShortcut.make(keyCode: 34, modifiers: .command, characters: "") == nil)
        let command = ImaYaruShortcut.make(keyCode: 34, modifiers: .command, characters: "i")
        #expect(command?.display == "⌘I")
        #expect(command?.carbonModifiers == UInt32(cmdKey))
        let shifted = ImaYaruShortcut.make(keyCode: 34, modifiers: [.command, .shift], characters: "i")
        #expect(shifted?.display == "⇧⌘I")
        #expect(shifted?.carbonModifiers == UInt32(cmdKey) | UInt32(shiftKey))
    }

    @Test func sectorHitTestReadsAngleAndDistance() {
        #expect(ImaYaruSectorHit.choice(dx: 0, dy: 0) == .click)
        #expect(ImaYaruSectorHit.choice(dx: 7, dy: 0) == .click)
        #expect(ImaYaruSectorHit.choice(dx: 0, dy: 7.9) == .click)
        #expect(ImaYaruSectorHit.choice(dx: 8, dy: 0) == .neutral)
        #expect(ImaYaruSectorHit.choice(dx: 29, dy: 0) == .neutral)

        #expect(ImaYaruSectorHit.choice(dx: 30, dy: 0) == .depart)
        #expect(ImaYaruSectorHit.choice(dx: 80, dy: 0) == .depart)
        #expect(ImaYaruSectorHit.choice(dx: 40, dy: -69) == .depart)
        #expect(ImaYaruSectorHit.choice(dx: 40, dy: -75) == .neutral)

        #expect(ImaYaruSectorHit.choice(dx: -80, dy: 0) == .save)
        #expect(ImaYaruSectorHit.choice(dx: -40, dy: -69) == .save)
        #expect(ImaYaruSectorHit.choice(dx: -40, dy: 69) == .save)
        #expect(ImaYaruSectorHit.choice(dx: -30, dy: -80) == .neutral)

        #expect(ImaYaruSectorHit.choice(dx: 0, dy: -80) == .neutral)
        #expect(ImaYaruSectorHit.choice(dx: 0, dy: 80) == .neutral)
        #expect(ImaYaruSectorHit.choice(dx: 30, dy: 80) == .neutral)
    }

    @Test func verticalStrokeMapsMinutesUpAndDownTheStops() {
        let pad: CGFloat = 200
        #expect(ImaYaruMinutesStroke.minutes(anchor: 30, dy: 0, padHeight: pad) == 30)
        #expect(ImaYaruMinutesStroke.minutes(anchor: 30, dy: -8, padHeight: pad) == 30)
        #expect(ImaYaruMinutesStroke.minutes(anchor: 30, dy: -40, padHeight: pad) == 45)
        #expect(ImaYaruMinutesStroke.minutes(anchor: 30, dy: -120, padHeight: pad) == 60)
        #expect(ImaYaruMinutesStroke.minutes(anchor: 60, dy: -80, padHeight: pad) == 60)
        #expect(ImaYaruMinutesStroke.minutes(anchor: 30, dy: 24, padHeight: pad) == 20)
        #expect(ImaYaruMinutesStroke.minutes(anchor: 45, dy: 200, padHeight: pad) == 5)
        #expect(ImaYaruMinutesStroke.minutes(anchor: 5, dy: 80, padHeight: pad) == 5)
    }

    @Test func calendarReleaseSavesAndAClosedServiceDeniesDepart() {
        #expect(ImaYaruRelease.resolve(choice: .depart, gate: .beforeService, canIssue: true) == .deny)
        #expect(ImaYaruRelease.resolve(choice: .neutral, gate: .beforeService, canIssue: true) == .none)
        #expect(ImaYaruRelease.resolve(choice: .save, gate: .beforeService, canIssue: true) == .save)
        #expect(ImaYaruRelease.resolve(choice: .depart, gate: .aboardCalendar, canIssue: true) == .save)
        #expect(ImaYaruRelease.resolve(choice: .neutral, gate: .aboardCalendar, canIssue: true) == .save)
        #expect(ImaYaruRelease.resolve(choice: .click, gate: .aboardCalendar, canIssue: true) == .close)
        #expect(ImaYaruRelease.resolve(choice: .neutral, gate: .open, canIssue: true) == .none)
        #expect(ImaYaruRelease.keyboard(commandReturn: true, gate: .beforeService, canIssue: true) == .save)
        #expect(ImaYaruRelease.keyboard(commandReturn: true, gate: .open, canIssue: true) == .depart)
        #expect(ImaYaruRelease.keyboard(commandReturn: false, gate: .open, canIssue: true) == .save)
    }

    @Test func machineGrowsToTheTicket() {
        let ticket = ImaYaruTicketMetrics.size
        #expect(ticket.width == ImaYaruTicketMetrics.width)
        #expect(abs(ticket.height - MarsTicketSpec.height(forWidth: ticket.width)) < 0.01)
        let fitted = ImaYaruMachineMetrics.fitted(ticket: ticket)
        #expect(abs(fitted.slotHeight - ticket.height) < 0.5)
        #expect(fitted.body.height > fitted.slotHeight)
        #expect(fitted.body.height < ticket.height * 1.4)
        #expect(fitted.slotWidth / fitted.body.width < 14.0 / 300.0 + 0.001)
        #expect(fitted.corner / fitted.body.height > 0.1)
    }

    @Test func flightTimelineMatchesTheF20Clock() {
        #expect(ImaYaruFlight.feedMs == 300)
        #expect(ImaYaruFlight.machineMs == 520)
        #expect(ImaYaruFlight.exitMs == 280)
        #expect(ImaYaruFlight.presentDwellMs == 100)
        #expect(ImaYaruFlight.machineDoneMs == 820)
        let geometry = ImaYaruFlightGeometry(
            ticketSize: ImaYaruTicketMetrics.size,
            origin: CGPoint(x: 200, y: 300),
            destination: CGPoint(x: 1400, y: 300),
            machineClearance: 500,
            direction: 1
        )
        let start = ImaYaruFlight.frame(tauMs: 0, geometry: geometry)
        #expect(start.ticketCenter == geometry.origin)
        #expect(start.machineShift == 0)
        #expect(start.printReveal == 0)
        let held = ImaYaruFlight.frame(tauMs: 350, geometry: geometry)
        #expect(held.ticketCenter.x > start.ticketCenter.x)
        #expect(held.stage == 2)
        let presented = ImaYaruFlight.frame(tauMs: ImaYaruFlight.presentEndMs, geometry: geometry)
        let gone = ImaYaruFlight.frame(tauMs: ImaYaruFlight.machineDoneMs, geometry: geometry)
        #expect(gone.finished)
        #expect(gone.machineShift < -400)
        #expect(gone.machineOpacity < 0.05)
        #expect(gone.catapultRetract > 0.95)
        #expect(gone.ticketCenter.x > presented.ticketCenter.x)
        let feeding = ImaYaruFlight.frame(tauMs: 240, geometry: geometry)
        #expect(feeding.machineOpacity > 0.95)
        let leaving = ImaYaruFlight.frame(tauMs: 680, geometry: geometry)
        #expect(leaving.machineShift < feeding.machineShift - 200)
        #expect(leaving.machineOpacity < 0.5)
    }

    @Test func shortcutRoundTripsAndDropsABareKey() {
        let defaults = UserDefaults(suiteName: "ima-yaru-shortcut-\(UUID().uuidString)")!
        #expect(ImaYaruShortcutStore.read(defaults) == nil)
        let made = ImaYaruShortcut.make(keyCode: 34, modifiers: .command, characters: "i")!
        ImaYaruShortcutStore.write(made, to: defaults)
        #expect(ImaYaruShortcutStore.read(defaults) == made)
        defaults.set(0, forKey: ImaYaruShortcutStore.modifiers)
        #expect(ImaYaruShortcutStore.read(defaults) == nil)
        ImaYaruShortcutStore.write(nil, to: defaults)
        #expect(defaults.object(forKey: ImaYaruShortcutStore.keyCode) == nil)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/tmp/imayaru-snapshots-dir")))
    @MainActor
    func writeF20Snapshots() throws {
        // The marker only exists for a local capture. CI never writes pictures.
        // The test host is sandboxed, so a failed file write falls back to the
        // pasteboard, which the shell can read.
        let root = (try? String(contentsOfFile: "/tmp/imayaru-snapshots-dir", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        let probe = directory.appendingPathComponent(".probe")
        let canWrite = FileManager.default.createFile(atPath: probe.path, contents: Data())
        if canWrite { try? FileManager.default.removeItem(at: probe) }
        var carried: [String] = []
        let ticket = ImaYaruTicketMetrics.size
        let stage = ImaYaruMachineMetrics.stage(ticket: ticket)
        let center = CGPoint(x: stage.width / 2, y: stage.height / 2 + 8)
        func render(_ name: String, _ picture: ImaYaruStagePicture) throws {
            let host = ImaYaruSnapshotHost(picture: picture, title: picture.ticketTitle)
                .frame(width: stage.width, height: stage.height)
            let data = try ImaYaruSnapshotHost.png(host, size: stage)
            if canWrite {
                try data.write(to: directory.appendingPathComponent(name))
            } else {
                carried.append(name)
                carried.append(data.base64EncodedString())
            }
        }
        try render("idle.png", ImaYaruSnapshotHost.picture(
            stage: stage, ticket: ticket, center: center, title: "資料の下書き", gate: .open, arm: .none
        ))
        try render("depart-lit.png", ImaYaruSnapshotHost.picture(
            stage: stage, ticket: ticket, center: center, title: "資料の下書き", gate: .open, arm: .depart, catapult: true
        ))
        try render("save-lit.png", ImaYaruSnapshotHost.picture(
            stage: stage, ticket: ticket, center: center, title: "資料の下書き", gate: .open, arm: .save
        ))
        try render("depart-disabled-calendar.png", ImaYaruSnapshotHost.picture(
            stage: stage, ticket: ticket, center: center, title: "資料の下書き", gate: .aboardCalendar, arm: .none
        ))

        let mouth = center.x + ImaYaruMachineMetrics.fitted(ticket: ticket).body.width / 2
        let geometry = ImaYaruFlightGeometry(
            ticketSize: ticket,
            origin: CGPoint(x: mouth - ticket.width / 2, y: center.y),
            destination: CGPoint(x: stage.width + ticket.width / 2 + 16, y: center.y),
            machineClearance: mouth + 16,
            direction: 1
        )
        let times: [Double] = [80, 240, 420, 680]
        var frames: [NSImage] = []
        for (index, tau) in times.enumerated() {
            let frame = ImaYaruFlight.frame(tauMs: tau, geometry: geometry)
            let picture = ImaYaruSnapshotHost.flightPicture(
                stage: stage, ticket: ticket, center: center, title: "資料の下書き", geometry: geometry, frame: frame
            )
            try render("depart-flight-\(index + 1).png", picture)
            let host = ImaYaruSnapshotHost(picture: picture, title: picture.ticketTitle)
                .frame(width: stage.width, height: stage.height)
            frames.append(try ImaYaruSnapshotHost.image(host, size: stage))
        }
        let strip = ImaYaruSnapshotHost.strip(frames)
        guard let data = ImaYaruSnapshotHost.pngData(strip) else {
            Issue.record("strip")
            return
        }
        if canWrite {
            try data.write(to: directory.appendingPathComponent("depart-flight.png"))
        } else {
            carried.append("depart-flight.png")
            carried.append(data.base64EncodedString())
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(carried.joined(separator: "\n"), forType: .string)
        }
    }
}

@MainActor
private struct ImaYaruSnapshotHost: View {
    @FocusState private var focus: Bool
    var picture: ImaYaruStagePicture
    var title: String

    var body: some View {
        ImaYaruStageView(
            title: .constant(title),
            picture: picture,
            interactive: false,
            titleFocused: $focus,
            onSubmitTitle: {},
            onMachineDrag: nil,
            onBackgroundDrag: nil
        )
        .background(Color(red: 38.0 / 255, green: 48.0 / 255, blue: 59.0 / 255))
    }

    static func picture(
        stage: CGSize,
        ticket: CGSize,
        center: CGPoint,
        title: String,
        gate: ImaYaruDepartGate,
        arm: ImaYaruArm,
        catapult: Bool = false
    ) -> ImaYaruStagePicture {
        let mouth = center.x + ImaYaruMachineMetrics.fitted(ticket: ticket).body.width / 2
        let length = ImaYaruFlight.railLength(stageWidth: stage.width, mouthX: mouth)
        return ImaYaruStagePicture(
            ticketTitle: title,
            minutes: 30,
            gate: gate,
            arm: arm,
            departCharge: arm == .depart ? 1 : 0,
            saveCharge: arm == .save ? 1 : 0,
            lamp: arm == .depart || arm == .save ? 1 : 0.35,
            slotOn: true,
            shake: 0,
            ticketSize: ticket,
            showTicket: false,
            ticketCenter: center,
            printReveal: 0,
            tilt: 0,
            machineCenter: center,
            mouthX: mouth,
            flightDirection: 0,
            catapult: catapult ? ImaYaruCatapultPicture(
                length: length,
                charge: 1,
                retract: 0,
                phase: 0.42,
                armed: true,
                launching: false,
                tip: 0
            ) : nil,
            notice: nil,
            reduceMotion: true,
            stageSize: stage
        )
    }

    static func flightPicture(
        stage: CGSize,
        ticket: CGSize,
        center: CGPoint,
        title: String,
        geometry: ImaYaruFlightGeometry,
        frame: ImaYaruFlightFrame
    ) -> ImaYaruStagePicture {
        let shift = frame.machineShift
        let machine = CGPoint(x: center.x + shift, y: center.y)
        let mouth = machine.x + ImaYaruMachineMetrics.fitted(ticket: ticket).body.width / 2
        let length = ImaYaruFlight.railLength(stageWidth: stage.width, mouthX: mouth)
        let leading = frame.ticketCenter.x + ticket.width / 2
        let tip = frame.stage >= 3 ? min(1, max(0, (leading - mouth) / length)) : 0
        return ImaYaruStagePicture(
            ticketTitle: title,
            minutes: 30,
            gate: .open,
            arm: .depart,
            departCharge: 1,
            saveCharge: 0,
            lamp: 1,
            slotOn: frame.slotOn,
            shake: 0,
            ticketSize: ticket,
            showTicket: true,
            ticketCenter: frame.ticketCenter,
            printReveal: frame.printReveal,
            tilt: 0,
            machineCenter: machine,
            mouthX: mouth,
            flightDirection: 1,
            catapult: ImaYaruCatapultPicture(
                length: max(length, 80),
                charge: 1,
                retract: frame.catapultRetract,
                phase: 0.42 + Double(frame.tip),
                armed: true,
                launching: frame.stage >= 3,
                tip: tip
            ),
            notice: nil,
            reduceMotion: true,
            stageSize: stage,
            machineOpacity: frame.machineOpacity
        )
    }

    static func png<V: View>(_ view: V, size: CGSize) throws -> Data {
        let image = try image(view, size: size)
        guard let data = pngData(image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    static func image<V: View>(_ view: V, size: CGSize) throws -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.nsImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        return image
    }

    static func strip(_ frames: [NSImage]) -> NSImage {
        let width = frames.reduce(0) { $0 + $1.size.width }
        let height = frames.map(\.size.height).max() ?? 0
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        let strip = NSImage(size: NSSize(width: width, height: height))
        if let rep {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            var x: CGFloat = 0
            for frame in frames {
                frame.draw(in: NSRect(x: x, y: 0, width: frame.size.width, height: frame.size.height))
                x += frame.size.width
            }
            NSGraphicsContext.restoreGraphicsState()
            strip.addRepresentation(rep)
        }
        return strip
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
