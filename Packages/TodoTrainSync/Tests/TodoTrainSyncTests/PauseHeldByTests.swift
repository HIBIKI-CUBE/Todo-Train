import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Pause heldBy")
struct PauseHeldByTests {
    let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let boundary = 1_768_000_000

    @Test func windowIsSixtySeconds() {
        #expect(PauseReasonResolving.windowSeconds == 60)
    }

    @Test func knownValuesMatchTheWireWords() {
        #expect(PauseHeldBy.knownRawValues == ["user", "timetable", "alarm", "switch", "passenger"])
        #expect(PauseHeldBy.user.rawValue == "user")
        #expect(PauseHeldBy.rideSwitch.rawValue == "switch")
        #expect(PauseHeldBy(rawValue: "switch") == .rideSwitch)
        #expect(PauseHeldBy(rawValue: "watch") == .unknown("watch"))
    }

    @Test func explicitUserAndTimetableAreKept() {
        #expect(PauseReasonResolving.resolve(heldBy: .user, arrivedAt: boundary, protectionBoundary: boundary) == .explicit(.user))
        #expect(PauseReasonResolving.resolve(heldBy: .timetable, arrivedAt: boundary + 10_000, protectionBoundary: nil) == .explicit(.timetable))
    }

    @Test func macOnlyValuesAndUnknownAreInvalidPayload() {
        for heldBy in [PauseHeldBy.alarm, .rideSwitch, .passenger, .unknown("watch"), .unknown("")] {
            #expect(PauseReasonResolving.rejectsPauseCommand(heldBy))
            #expect(PauseReasonResolving.resolve(heldBy: heldBy, arrivedAt: boundary, protectionBoundary: boundary) == .invalidPayload)
            let decision = RemotePauseEvaluating.evaluate(
                openSessionId: session,
                pausedCount: 0,
                pauseLimit: 2,
                command: pause(heldBy: heldBy)
            )
            #expect(decision == .invalidPayload)
            #expect(!decision.shouldApply)
            #expect(RemotePauseEvaluating.ack(decision: decision, commandId: session).error == .invalidPayload)
        }
    }

    @Test func missingHeldByInsideTheWindowInfersTimetable() {
        for delta in [-60, 0, 60] {
            let record = PauseReasonResolving.resolve(
                heldBy: nil,
                arrivedAt: boundary + delta,
                protectionBoundary: boundary
            )
            #expect(record == .inferred(.timetable))
        }
    }

    @Test func missingHeldByOutsideTheWindowInfersUser() {
        for delta in [-61, 61, 10_000] {
            let record = PauseReasonResolving.resolve(
                heldBy: nil,
                arrivedAt: boundary + delta,
                protectionBoundary: boundary
            )
            #expect(record == .inferred(.user))
        }
        #expect(PauseReasonResolving.resolve(heldBy: nil, arrivedAt: boundary, protectionBoundary: nil) == .inferred(.user))
        #expect(!PauseReasonResolving.rejectsPauseCommand(nil))
    }

    @Test func alarmOnTheWireDecodesAndIsRejected() throws {
        let raw = """
        {"id":"33333333-3333-4333-8333-333333333333","op":"pause","sessionId":"11111111-1111-4111-8111-111111111111","at":1768000120,"heldBy":"alarm"}
        """
        let command = try WireJSON.decoder().decode(CommandPlaintext.self, from: Data(raw.utf8))
        #expect(command.heldBy == .alarm)
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: session,
            pausedCount: 0,
            pauseLimit: 2,
            command: command
        )
        #expect(decision == .invalidPayload)
    }

    @Test func snapKeepsAnUnknownPauseHeldByWhilePaused() throws {
        let raw = """
        {"rev":1,"sessionId":"11111111-1111-4111-8111-111111111111","ticketId":null,"title":"a","phase":"paused","startedAt":1,"estimatedSeconds":60,"pausedAccumulated":0,"pausedAt":2,"boardedDeviceID":null,"serviceActive":true,"cabinEnabled":true,"checkInFiredCount":0,"pendingCabin":null,"pauseHeldBy":"watch"}
        """
        let snap = try WireJSON.decoder().decode(SnapPlaintext.self, from: Data(raw.utf8))
        #expect(snap.pauseHeldBy == .unknown("watch"))
        let object = try JSONSerialization.jsonObject(with: try WireJSON.encoder().encode(snap)) as! [String: Any]
        #expect(object["pauseHeldBy"] as? String == "watch")
    }

    private func pause(heldBy: PauseHeldBy) -> CommandPlaintext {
        CommandPlaintext(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            op: .pause,
            sessionId: session,
            at: boundary,
            heldBy: heldBy
        )
    }
}
