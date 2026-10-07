import Foundation
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

struct ImaYaruTests {
    @Test func canvasSizeDoesNotChangeWithPhase() {
        let phases: [ImaYaruPhase] = [.composing, .ejecting, .holding, .failed]
        let first = ImaYaruCanvas.size(for: .composing)
        for phase in phases {
            #expect(ImaYaruCanvas.size(for: phase) == first)
        }
        #expect(ImaYaruCanvas.size.width == 440)
        #expect(ImaYaruCanvas.ticketSlotHeight > 0)
        #expect(ImaYaruCanvas.size.height > ImaYaruCanvas.titleRail + ImaYaruCanvas.gaugeRail)
    }

    @Test func offerRequiresPairAndService() {
        #expect(ImaYaruOffer.isAvailable(isPaired: true, serviceActive: true))
        #expect(!ImaYaruOffer.isAvailable(isPaired: true, serviceActive: false))
        #expect(!ImaYaruOffer.isAvailable(isPaired: true, serviceActive: nil))
        #expect(!ImaYaruOffer.isAvailable(isPaired: false, serviceActive: true))
    }

    @Test func snapConfirmsANewRideOnly() {
        let prior = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let fresh = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let snap = SnapPlaintext(
            rev: 2,
            sessionId: fresh,
            ticketId: UUID(),
            title: "週次レビュー",
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
}
