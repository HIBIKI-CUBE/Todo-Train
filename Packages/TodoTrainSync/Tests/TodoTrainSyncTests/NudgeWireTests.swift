import Foundation
import Testing
@testable import TodoTrainSync

/// Field set of the snap an installed client decodes. Unknown keys are ignored.
private struct InstalledSnap: Decodable {
    var rev: Int
    var sessionId: String?
    var title: String?
    var phase: String
    var pendingCabin: String?
    var serviceActive: Bool?
}

@Suite("Nudge wire")
struct NudgeWireTests {
    private let session = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let nudge = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    private let reserved = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!

    @Test func installedAndCurrentTypesReadSnapsWithAndWithoutNudgeFields() throws {
        let missing = try ContractFixtures.data("fixtures/v4/snap.json")
        let present = try ContractFixtures.data("fixtures/snap-nudge.json")

        let installedMissing = try JSONDecoder().decode(InstalledSnap.self, from: missing)
        let installedPresent = try JSONDecoder().decode(InstalledSnap.self, from: present)
        #expect(installedMissing.title == "週次レポート")
        #expect(installedMissing.pendingCabin == nil)
        #expect(installedPresent.rev == 44)
        #expect(installedPresent.phase == "running")
        #expect(installedPresent.pendingCabin == "progress")

        let currentMissing = try WireJSON.decoder().decode(SnapPlaintext.self, from: missing)
        let currentPresent = try WireJSON.decoder().decode(SnapPlaintext.self, from: present)
        #expect(currentMissing.nudge == nil)
        #expect(currentMissing.nudgePlan == nil)
        #expect(currentMissing.reserved == nil)
        #expect(currentPresent.nudge?.id == nudge)
        #expect(currentPresent.nudge?.kind == .progress)
        #expect(currentPresent.nudge?.stage == .checkIn)
        #expect(currentPresent.nudge?.ringSurface == .mac)
        #expect(currentPresent.nudge?.firedAt == 1_768_000_900)
        #expect(currentPresent.pendingCabin == .progress)
        #expect(currentPresent.nudgePlan?.count == 2)
        #expect(currentPresent.nudgePlan?.first?.rings == false)
        #expect(currentPresent.nudgePlan?.last?.stage == .estimate)
        #expect(currentPresent.reserved?.ticketId == reserved)
        #expect(currentPresent.reserved?.estimatedSeconds == 900)

        let encodedMissing = try WireJSON.encoder().encode(currentMissing)
        let missingObject = try JSONSerialization.jsonObject(with: encodedMissing) as! [String: Any]
        #expect(missingObject["nudge"] == nil)
        #expect(missingObject["nudgePlan"] == nil)
        #expect(missingObject["reserved"] == nil)

        let again = try WireJSON.decoder().decode(SnapPlaintext.self, from: try WireJSON.encoder().encode(currentPresent))
        #expect(again == currentPresent)
    }

    @Test func stageNamesMatchThePlanner() {
        let wire = Set(NudgeStageWire.knownRawValues)
        #expect(Set(NudgeStage.allCases.map(\.rawValue)).isSubset(of: wire))
        #expect(Set(NudgeGap.allCases.map(\.rawValue)).isSubset(of: wire))
        #expect(NudgeStageWire(rawValue: "watch") == .unknown("watch"))
        #expect(NudgeRingSurface(rawValue: NudgeSurface.watch.rawValue) == .unknown("watch"))
    }

    @Test func answerExtendAndArriveRoundTrip() throws {
        let extend = try WireJSON.decoder().decode(
            CommandPlaintext.self,
            from: ContractFixtures.data("fixtures/v14/cmd-answer-extend.json")
        )
        #expect(extend.op == .answer)
        #expect(extend.choice == .willExtend)
        #expect(extend.addSeconds == 600)
        #expect(extend.answeredOn == .mac)
        #expect(extend.nudgeId == nudge)
        let extendObject = try json(extend)
        #expect(extendObject["addSeconds"] as? Int == 600)
        #expect(extendObject["ticketId"] == nil)
        #expect(extendObject["pipVisible"] == nil)

        let arrive = try WireJSON.decoder().decode(
            CommandPlaintext.self,
            from: ContractFixtures.data("fixtures/cmd-answer-arrive.json")
        )
        #expect(arrive.choice == .alreadyDone)
        #expect(arrive.addSeconds == nil)
        let arriveObject = try json(arrive)
        #expect(arriveObject["addSeconds"] == nil)
        #expect(arriveObject["choice"] as? String == "alreadyDone")
    }

    @Test func boardReservedAndPresenceRoundTrip() throws {
        let board = try WireJSON.decoder().decode(
            CommandPlaintext.self,
            from: ContractFixtures.data("fixtures/cmd-boardReserved.json")
        )
        #expect(board.op == .boardReserved)
        #expect(board.sessionId == nil)
        #expect(board.ticketId == reserved)
        #expect(board.nudgeId == nudge)
        #expect(board.title == nil)
        let boardObject = try json(board)
        #expect(boardObject["sessionId"] is NSNull)
        #expect(boardObject["choice"] == nil)

        let presence = try WireJSON.decoder().decode(
            CommandPlaintext.self,
            from: ContractFixtures.data("fixtures/cmd-presence.json")
        )
        #expect(presence.op == .presence)
        #expect(presence.pipVisible == true)
        #expect(presence.attending == false)
        #expect(presence.sessionId == nil)
        let presenceObject = try json(presence)
        #expect(presenceObject["attending"] as? Bool == false)
        #expect(presenceObject["nudgeId"] == nil)
    }

    @Test func nudgeStaleAckRoundTrip() throws {
        let ack = try WireJSON.decoder().decode(
            AckPlaintext.self,
            from: ContractFixtures.data("fixtures/ack-nudgeStale.json")
        )
        #expect(ack.ok == false)
        #expect(ack.error == .nudgeStale)
        let again = try WireJSON.decoder().decode(AckPlaintext.self, from: try WireJSON.encoder().encode(ack))
        #expect(again == ack)
        #expect(MenuBarPresentation.failureCopy(.nudgeStale) == "この声掛けは終わりました")
        #expect(MenuBarPresentation.failureCopy(.noReservation) == "予約なし")
        #expect(MenuBarPresentation.failureCopy(.reservationChanged) == "予約が変わりました")
    }

    @Test func pauseOmitsNudgeKeys() throws {
        let pause = try WireJSON.decoder().decode(
            CommandPlaintext.self,
            from: ContractFixtures.data("fixtures/cmd-pause.json")
        )
        let object = try json(pause)
        for key in ["nudgeId", "choice", "addSeconds", "answeredOn", "ticketId", "pipVisible", "attending", "heldBy"] {
            #expect(object[key] == nil, "pause must omit \(key)")
        }
    }

    @Test func addSecondsOutsideThePresetsIsInvalidPayload() {
        for seconds in [0, 60, 299, 301, 900 + 1, 1200] {
            let command = answer(choice: .willExtend, addSeconds: seconds)
            #expect(NudgeCommandEvaluating.evaluate(
                command: command,
                openSessionId: session,
                currentNudgeId: nudge
            ) == .invalidPayload)
        }
        let missing = answer(choice: .willExtend, addSeconds: nil)
        #expect(NudgeCommandEvaluating.evaluate(
            command: missing,
            openSessionId: session,
            currentNudgeId: nudge
        ) == .invalidPayload)
        let extra = answer(choice: .alreadyDone, addSeconds: 300)
        #expect(NudgeCommandEvaluating.evaluate(
            command: extra,
            openSessionId: session,
            currentNudgeId: nudge
        ) == .invalidPayload)
        for seconds in [300, 600, 900] {
            let command = answer(choice: .willExtend, addSeconds: seconds)
            #expect(NudgeCommandEvaluating.evaluate(
                command: command,
                openSessionId: session,
                currentNudgeId: nudge
            ) == .accept)
        }
    }

    @Test func answerContextErrors() {
        let command = answer(choice: .stillOnIt, addSeconds: nil)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            openSessionId: UUID(),
            currentNudgeId: nudge
        ) == .sessionMismatch)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            openSessionId: session,
            currentNudgeId: UUID()
        ) == .nudgeStale)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            openSessionId: session,
            currentNudgeId: nil
        ) == .nudgeStale)
        var watch = command
        watch.answeredOn = .unknown("watch")
        #expect(NudgeCommandEvaluating.evaluate(
            command: watch,
            openSessionId: session,
            currentNudgeId: nudge
        ) == .invalidPayload)
    }

    @Test func boardReservedErrors() {
        let command = CommandPlaintext(
            id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!,
            op: .boardReserved,
            sessionId: nil,
            at: 1_768_002_000,
            nudgeId: nudge,
            ticketId: reserved
        )
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            serviceActive: false,
            reservedTicketId: reserved
        ) == .noActiveService)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            serviceActive: true,
            openSessionId: session,
            reservedTicketId: reserved
        ) == .sessionMismatch)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            serviceActive: true,
            reservedTicketId: nil
        ) == .noReservation)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            serviceActive: true,
            reservedTicketId: UUID()
        ) == .reservationChanged)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            serviceActive: true,
            reservedTicketId: reserved
        ) == .accept)
    }

    @Test func olderContractRejectsTheNewOps() {
        let command = answer(choice: .paused, addSeconds: nil)
        #expect(NudgeCommandEvaluating.evaluate(
            command: command,
            openSessionId: session,
            currentNudgeId: nudge,
            receiverContract: 4
        ) == .unsupportedOp)
        #expect(NudgeCommandEvaluating.versionGate(op: .presence, receiverContract: 4) == .unsupportedOp)
        #expect(NudgeCommandEvaluating.versionGate(op: .answer, receiverContract: 5) == nil)
        #expect(NudgeCommandEvaluating.versionGate(op: .unknown("arrive"), receiverContract: 5) == .unsupportedOp)
    }

    @Test func pauseEvaluatorDoesNotApplyAnswer() {
        let decision = RemotePauseEvaluating.evaluate(
            openSessionId: session,
            pausedCount: 0,
            pauseLimit: 3,
            command: answer(choice: .paused, addSeconds: nil)
        )
        #expect(decision == .unsupportedOp)
        #expect(!decision.shouldApply)
    }

    @Test func malformedNudgeAndReservedLeaveTheRestOfTheSnap() throws {
        let present = try ContractFixtures.data("fixtures/snap-nudge.json")
        var object = try #require(JSONSerialization.jsonObject(with: present) as? [String: Any])
        object["nudge"] = ["id": "not-a-uuid"]
        object["reserved"] = "nope"
        object["nudgePlan"] = [["stage": 1]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let snap = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
        #expect(snap.rev == 44)
        #expect(snap.phase == .running)
        #expect(snap.nudge == nil)
        #expect(snap.reserved == nil)
        #expect(snap.nudgePlan == nil)
        #expect(snap.pendingCabin == .progress)
    }

    private func answer(choice: NudgeChoice, addSeconds: Int?) -> CommandPlaintext {
        CommandPlaintext(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            op: .answer,
            sessionId: session,
            at: 1_768_000_910,
            nudgeId: nudge,
            choice: choice,
            addSeconds: addSeconds,
            answeredOn: .mac
        )
    }

    private func json(_ command: CommandPlaintext) throws -> [String: Any] {
        let encoded = try WireJSON.encoder().encode(command)
        return try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    }
}
