import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Golden JSON round-trip")
struct GoldenJSONTests {
    @Test func snapRunningRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/snap.json")
        let decoded = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
        #expect(decoded.rev == 42)
        #expect(decoded.sessionId == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        #expect(decoded.ticketId == UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        #expect(decoded.title == "週次レポート")
        #expect(decoded.phase == .running)
        #expect(decoded.startedAt == 1_768_000_000)
        #expect(decoded.estimatedSeconds == 1500)
        #expect(decoded.pausedAccumulated == 0)
        #expect(decoded.pausedAt == nil)
        #expect(decoded.boardedDeviceID == "phone-a")
        #expect(decoded.serviceActive == true)
        #expect(decoded.cabinEnabled == true)
        #expect(decoded.checkInFiredCount == 0)
        #expect(decoded.pendingCabin == nil)

        let encoded = try WireJSON.encoder().encode(decoded)
        let again = try WireJSON.decoder().decode(SnapPlaintext.self, from: encoded)
        #expect(again == decoded)

        let original = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let round = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        #expect(original?["title"] as? String == round?["title"] as? String)
        #expect(original?["rev"] as? Int == round?["rev"] as? Int)
        #expect(round?["pausedAt"] is NSNull)
    }

    @Test func snapIdleRoundTripKeepsNulls() throws {
        let data = try ContractFixtures.data("fixtures/snap-idle.json")
        let decoded = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
        #expect(decoded.phase == .idle)
        #expect(decoded.sessionId == nil)
        #expect(decoded.title == nil)
        #expect(decoded.remainingSeconds(at: 1_768_000_120) == nil)

        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        for key in ["sessionId", "ticketId", "title", "startedAt", "estimatedSeconds", "pausedAccumulated", "pausedAt", "boardedDeviceID", "pendingCabin"] {
            #expect(object[key] is NSNull, "idle snap must emit null for \(key)")
        }
        #expect(object["phase"] as? String == "idle")
        #expect(object["rev"] as? Int == 43)
        #expect(object["serviceActive"] as? Bool == false)
        #expect(object["cabinEnabled"] as? Bool == true)
        #expect(object["checkInFiredCount"] as? Int == 0)
    }

    @Test func cmdPauseRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/cmd-pause.json")
        let decoded = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
        #expect(decoded.op == .pause)
        #expect(decoded.id == UUID(uuidString: "33333333-3333-4333-8333-333333333333"))
        #expect(decoded.sessionId == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        #expect(decoded.at == 1_768_000_120)

        let encoded = try WireJSON.encoder().encode(decoded)
        let again = try WireJSON.decoder().decode(CommandPlaintext.self, from: encoded)
        #expect(again == decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["op"] as? String == "pause")
        #expect((object["id"] as? String)?.contains("A") == false)
        #expect(object["title"] == nil)
        #expect(object["estimatedSeconds"] == nil)
    }

    @Test func cmdIssueAndBoardRoundTripOmitsNothingRequired() throws {
        let data = try ContractFixtures.data("fixtures/cmd-issueAndBoard.json")
        let decoded = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
        #expect(decoded.op == .issueAndBoard)
        #expect(decoded.sessionId == nil)
        #expect(decoded.title == "週次レビューの下書き")
        #expect(decoded.estimatedSeconds == 1500)

        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["title"] as? String == "週次レビューの下書き")
        #expect(object["estimatedSeconds"] as? Int == 1500)
        #expect(object["sessionId"] is NSNull)
        #expect(object.keys.sorted() == ["at", "estimatedSeconds", "id", "op", "sessionId", "title"])
    }

    @Test func cmdIssueAndBoardInterruptKeepsSession() throws {
        let data = try ContractFixtures.data("fixtures/cmd-issueAndBoard-interrupt.json")
        let decoded = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
        #expect(decoded.op == .issueAndBoard)
        #expect(decoded.sessionId == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        #expect(decoded.estimatedSeconds == 600)
        #expect(decoded.title == "割り込みの下書き")
    }

    @Test func cmdStillRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/cmd-still.json")
        let decoded = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
        #expect(decoded.op == .still)
        #expect(decoded.id == UUID(uuidString: "55555555-5555-4555-8555-555555555555"))
        #expect(decoded.sessionId == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))

        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["op"] as? String == "still")
    }

    @Test func cmdStillNullSessionDecodes() throws {
        let data = try ContractFixtures.data("fixtures/cmd-still-nosession.json")
        let decoded = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
        #expect(decoded.op == .still)
        #expect(decoded.sessionId == nil)
        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["sessionId"] is NSNull)
    }

    @Test func oldSnapMissingCabinKeysDefaults() throws {
        let json = Data(#"{"rev":1,"sessionId":null,"ticketId":null,"title":null,"phase":"idle","startedAt":null,"estimatedSeconds":null,"pausedAccumulated":null,"pausedAt":null,"boardedDeviceID":null}"#.utf8)
        let decoded = try WireJSON.decoder().decode(SnapPlaintext.self, from: json)
        #expect(decoded.serviceActive == false)
        #expect(decoded.cabinEnabled == true)
        #expect(decoded.checkInFiredCount == 0)
        #expect(decoded.pendingCabin == nil)
    }

    @Test func pendingCabinIdleIsNotUnknown() throws {
        let json = Data(#"{"rev":1,"sessionId":null,"ticketId":null,"title":null,"phase":"idle","startedAt":null,"estimatedSeconds":null,"pausedAccumulated":null,"pausedAt":null,"boardedDeviceID":null,"serviceActive":true,"cabinEnabled":true,"checkInFiredCount":0,"pendingCabin":"idle"}"#.utf8)
        let decoded = try WireJSON.decoder().decode(SnapPlaintext.self, from: json)
        #expect(decoded.pendingCabin == .idle)
        #expect(decoded.serviceActive == true)
    }

    @Test func cmdResumeRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/cmd-resume.json")
        let decoded = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
        #expect(decoded.op == .resume)
        #expect(decoded.id == UUID(uuidString: "44444444-4444-4444-8444-444444444444"))
        #expect(decoded.sessionId == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))

        let encoded = try WireJSON.encoder().encode(decoded)
        let again = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(again["op"] as? String == "resume")
        #expect((again["id"] as? String)?.contains("A") == false)
    }

    @Test func oldSnapWithoutBuildDecodes() throws {
        let data = try ContractFixtures.data("fixtures/snap.json")
        let decoded = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
        #expect(decoded.build == nil)
        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["build"] == nil)
    }

    @Test func partialBuildIsIgnoredAndSnapStillDecodes() throws {
        let fixtures = [
            "fixtures/snap.json",
            "fixtures/ack-ok.json",
            "fixtures/cmd-pause.json",
        ]
        for relative in fixtures {
            let original = try ContractFixtures.data(relative)
            var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
            object["build"] = ["sha": "abc"]
            let data = try JSONSerialization.data(withJSONObject: object)
            switch relative {
            case "fixtures/snap.json":
                let snap = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
                #expect(snap.build == nil)
                #expect(snap.title == "週次レポート")
            case "fixtures/ack-ok.json":
                let ack = try WireJSON.decoder().decode(AckPlaintext.self, from: data)
                #expect(ack.build == nil)
                #expect(ack.ok)
            default:
                let command = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
                #expect(command.build == nil)
                #expect(command.op == .pause)
            }
        }
    }

    @Test func snapBuildRoundTripOmitsWhenNil() throws {
        let build = WireBuildInfo(sha: "1047101", dirty: true, schema: "3.0.0", builtAt: "2026-10-12T16:20:00+09:00")
        var snap = try WireJSON.decoder().decode(
            SnapPlaintext.self,
            from: ContractFixtures.data("fixtures/snap-idle.json")
        )
        #expect(snap.build == nil)
        snap.build = build
        let encoded = try WireJSON.encoder().encode(snap)
        let again = try WireJSON.decoder().decode(SnapPlaintext.self, from: encoded)
        #expect(again.build == build)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        let nested = try #require(object["build"] as? [String: Any])
        #expect(nested["sha"] as? String == "1047101")
        #expect(nested["dirty"] as? Bool == true)
        #expect(nested["schema"] as? String == "3.0.0")
    }

    @Test func ackOkOmitsErrorKey() throws {
        let data = try ContractFixtures.data("fixtures/ack-ok.json")
        let decoded = try WireJSON.decoder().decode(AckPlaintext.self, from: data)
        #expect(decoded.ok)
        #expect(decoded.error == nil)

        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["ok"] as? Bool == true)
        #expect(object["error"] == nil)
        #expect(object.keys.sorted() == ["cmdId", "ok"])
    }

    @Test func ackWithoutBuildStaysCompatibleAndWithBuildRoundTrips() throws {
        let old = try WireJSON.decoder().decode(
            AckPlaintext.self,
            from: ContractFixtures.data("fixtures/ack-ok.json")
        )
        #expect(old.build == nil)
        let build = WireBuildInfo(sha: "abcdef1", dirty: false, schema: "3.0.0", builtAt: "2026-10-12T16:20:00+09:00")
        let ack = AckPlaintext(cmdId: old.cmdId, ok: true, build: build)
        let encoded = try WireJSON.encoder().encode(ack)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["error"] == nil)
        #expect((object["build"] as? [String: Any])?["sha"] as? String == "abcdef1")
        let again = try WireJSON.decoder().decode(AckPlaintext.self, from: encoded)
        #expect(again == ack)
    }

    @Test func commandWithoutBuildOmitsKeyAndWithBuildRoundTrips() throws {
        let old = try WireJSON.decoder().decode(
            CommandPlaintext.self,
            from: ContractFixtures.data("fixtures/cmd-pause.json")
        )
        #expect(old.build == nil)
        let encodedOld = try WireJSON.encoder().encode(old)
        let oldObject = try JSONSerialization.jsonObject(with: encodedOld) as! [String: Any]
        #expect(oldObject["build"] == nil)

        let build = WireBuildInfo(sha: "abcdef1", dirty: false, schema: "3.0.0", builtAt: "2026-10-12T16:20:00+09:00")
        let command = CommandPlaintext(
            id: old.id,
            op: old.op,
            sessionId: old.sessionId,
            at: old.at,
            build: build
        )
        let encoded = try WireJSON.encoder().encode(command)
        let again = try WireJSON.decoder().decode(CommandPlaintext.self, from: encoded)
        #expect(again.build == build)
        #expect(again.title == nil)
    }

    @Test func ackUnsupportedOpRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/ack-unsupportedOp.json")
        let decoded = try WireJSON.decoder().decode(AckPlaintext.self, from: data)
        #expect(!decoded.ok)
        #expect(decoded.error == .unsupportedOp)
        let encoded = try WireJSON.encoder().encode(decoded)
        let again = try WireJSON.decoder().decode(AckPlaintext.self, from: encoded)
        #expect(again == decoded)
    }

    @Test func ackPauseLimitRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/ack-pauseLimitReached.json")
        let decoded = try WireJSON.decoder().decode(AckPlaintext.self, from: data)
        #expect(!decoded.ok)
        #expect(decoded.error == .pauseLimitReached)

        let encoded = try WireJSON.encoder().encode(decoded)
        let again = try WireJSON.decoder().decode(AckPlaintext.self, from: encoded)
        #expect(again == decoded)
    }

    @Test func unknownPhaseDoesNotCrash() throws {
        let json = Data(#"{"rev":1,"sessionId":null,"ticketId":null,"title":null,"phase":"boarding","startedAt":null,"estimatedSeconds":null,"pausedAccumulated":null,"pausedAt":null,"boardedDeviceID":null}"#.utf8)
        let decoded = try WireJSON.decoder().decode(SnapPlaintext.self, from: json)
        #expect(decoded.phase == .unknown("boarding"))
        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["phase"] as? String == "boarding")
    }

    @Test func constantsMatchContract() throws {
        let data = try ContractFixtures.data("constants.json")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Int]
        #expect(json["offerTtlSeconds"] == SyncConstants.offerTtlSeconds)
        #expect(json["confirmOverlapWindowSeconds"] == SyncConstants.confirmOverlapWindowSeconds)
        #expect(json["cmdFifoMax"] == SyncConstants.cmdFifoMax)
    }

    @Test func enumsMatchContract() throws {
        let data = try ContractFixtures.data("enums.json")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["phase"] as? [String] == ["idle", "running", "paused", "overtime"])
        #expect(json["kind"] as? [String] == ["snap", "cmd", "ack"])
        #expect(json["op"] as? [String] == ["pause", "resume", "still", "issueAndBoard"])
        #expect(json["pendingCabin"] as? [String] == ["progress", "away", "idle"])
        #expect(json["error"] as? [String] == [
            "pauseLimitReached", "noActiveService", "sessionMismatch", "decryptFailed", "notPaused",
            "invalidPayload", "unsupportedOp",
        ])
    }
}
