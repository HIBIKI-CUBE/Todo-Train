import CoreGraphics
import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

struct ImaYaruTests {
    @Test func offerRequiresPairAndService() {
        #expect(ImaYaruOffer.isAvailable(isPaired: true, serviceActive: true))
        #expect(!ImaYaruOffer.isAvailable(isPaired: true, serviceActive: false))
        #expect(!ImaYaruOffer.isAvailable(isPaired: true, serviceActive: nil))
        #expect(!ImaYaruOffer.isAvailable(isPaired: false, serviceActive: true))
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
        #expect(entry.size == rest.size)
        #expect(entry.maxY < display.minY)
        #expect(entry.minX == rest.minX)
    }
}
