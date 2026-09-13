import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Hint polling")
struct HintPollingTests {
    let running = HintPlaintext(snapRev: 42, ackRev: 7, cmdCount: 1)
    let idle = HintPlaintext(snapRev: 0, ackRev: 0, cmdCount: 0)

    @Test func goldenHintRoundTrip() throws {
        let data = try ContractFixtures.data("fixtures/hint.json")
        let decoded = try WireJSON.decoder().decode(HintPlaintext.self, from: data)
        #expect(decoded == running)
        let encoded = try WireJSON.encoder().encode(decoded)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        #expect(object["snapRev"] as? Int == 42)
        #expect(object["ackRev"] as? Int == 7)
        #expect(object["cmdCount"] as? Int == 1)
        #expect(object["ct"] == nil)
    }

    @Test func pollsOnlyWhileDisconnectedAndPaired() {
        #expect(HintPolling.shouldPoll(isPaired: true, connection: .disconnected))
        #expect(!HintPolling.shouldPoll(isPaired: true, connection: .connected))
        #expect(!HintPolling.shouldPoll(isPaired: false, connection: .disconnected))
    }

    @Test func etagMatchesContractShape() {
        #expect(HintPolling.etag(for: running) == "\"42-7-1\"")
    }

    @Test func macCatchesSnapAndAckChanges() {
        let first = HintPolling.catchUp(previous: nil, current: running, subscriber: .mac)
        #expect(first.snap)
        #expect(first.ack)
        #expect(!first.cmd)

        let same = HintPolling.catchUp(previous: running, current: running, subscriber: .mac)
        #expect(!same.needsFetch)

        var next = running
        next.snapRev = 43
        let snapOnly = HintPolling.catchUp(previous: running, current: next, subscriber: .mac)
        #expect(snapOnly.snap)
        #expect(!snapOnly.ack)
    }

    @Test func iphoneFetchesCmdWhileCountPositive() {
        let first = HintPolling.catchUp(previous: nil, current: running, subscriber: .iphone)
        #expect(!first.snap)
        #expect(!first.ack)
        #expect(first.cmd)

        let stillPending = HintPolling.catchUp(previous: running, current: running, subscriber: .iphone)
        #expect(stillPending.cmd)

        let cleared = HintPolling.catchUp(previous: running, current: idle, subscriber: .iphone)
        #expect(!cleared.cmd)
    }

    @Test func outcomeStopsOn429AndIgnores304() {
        #expect(
            HintPolling.outcome(
                subscriber: .mac,
                previous: running,
                status: 304,
                hint: nil,
                responseETag: "\"42-7-1\""
            ) == .ignore
        )
        #expect(
            HintPolling.outcome(
                subscriber: .mac,
                previous: running,
                status: 429,
                hint: nil,
                responseETag: nil
            ) == .stop
        )
        #expect(
            HintPolling.outcome(
                subscriber: .mac,
                previous: running,
                status: 401,
                hint: nil,
                responseETag: nil
            ) == .stop
        )
        #expect(
            HintPolling.outcome(
                subscriber: .mac,
                previous: running,
                status: 404,
                hint: nil,
                responseETag: nil
            ) == .ignore
        )
        let caught = HintPolling.outcome(
            subscriber: .mac,
            previous: nil,
            status: 200,
            hint: running,
            responseETag: "\"42-7-1\""
        )
        #expect(caught == .catchUp(
            HintCatchUp(snap: true, ack: true, cmd: false),
            hint: running,
            etag: "\"42-7-1\""
        ))
    }

    @Test func intervalIsFiveSeconds() {
        #expect(HintPolling.intervalNanoseconds == 5_000_000_000)
    }
}
