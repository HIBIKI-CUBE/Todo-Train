import Foundation
import Testing
@testable import TodoTrainSync

@Suite("WebSocket control frames")
struct WSControlTests {
    private let id = UUID(uuidString: "a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea")!

    private func decode(_ text: String) throws -> WSIncoming {
        try WSIncoming.decode(Data(text.utf8))
    }

    @Test func helloCarriesRoleOnlyWhenGiven() throws {
        let announcement = ContractAnnouncement(contract: 16, minReadable: 3)
        #expect(ContractHello.text(announcement) == #"{"t":"hello","contract":16,"minReadable":3}"#)
        #expect(
            ContractHello.text(announcement, role: .iphone)
                == #"{"t":"hello","contract":16,"minReadable":3,"role":"iphone"}"#
        )
        #expect(
            ContractHello.text(announcement, role: .mac)
                == #"{"t":"hello","contract":16,"minReadable":3,"role":"mac"}"#
        )
    }

    @Test func helloWithRoleMatchesContractExample() throws {
        let data = try ContractFixtures.data("ws.json")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hello = try #require(json["hello"] as? [String: Any])
        let example = try #require(hello["clientWithRole"] as? [String: Any])
        let ours = try #require(
            JSONSerialization.jsonObject(
                with: Data(ContractHello.text(ContractAnnouncement(contract: 16, minReadable: 3), role: .iphone).utf8)
            ) as? [String: Any]
        )
        #expect(NSDictionary(dictionary: ours).isEqual(to: example))
    }

    @Test func encodesLowercaseIds() {
        #expect(WSControl.ping(id: id) == #"{"t":"ping","id":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"}"#)
        #expect(WSControl.echo(id: id) == #"{"t":"echo","id":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"}"#)
        #expect(WSControl.ping(id: id).utf8.count <= WSControl.maxBytes)
    }

    @Test func decodesPingPongEcho() throws {
        let text = id.canonicalLowercase
        #expect(try decode(#"{"t":"ping","id":"\#(text)"}"#) == .ping(id))
        #expect(try decode(#"{"t":"pong","id":"\#(text)"}"#) == .pong(id))
        #expect(try decode(#"{"t":"echo","id":"\#(text)","mac":true}"#) == .echo(id: id, mac: true))
        #expect(try decode(#"{"t":"echo","id":"\#(text)","mac":false}"#) == .echo(id: id, mac: false))
    }

    @Test func rejectsBadControlFrames() {
        #expect(throws: SyncError.invalidJSON) { try decode(#"{"t":"ping","id":"A1A2A3A4-B1B2-4C3C-8D4D-E5E6E7E8E9EA"}"#) }
        #expect(throws: SyncError.invalidJSON) { try decode(#"{"t":"pong","id":"not-a-uuid"}"#) }
        #expect(throws: SyncError.invalidJSON) { try decode(#"{"t":"echo"}"#) }
        let padding = String(repeating: "x", count: 300)
        #expect(throws: SyncError.invalidJSON) {
            try decode(#"{"t":"ping","id":"\#(id.canonicalLowercase)","pad":"\#(padding)"}"#)
        }
    }

    @Test func helloAndFramesStillDecode() throws {
        #expect(try decode(#"{"t":"hello","contract":16,"minReadable":3}"#) == .hello(ContractAnnouncement(contract: 16, minReadable: 3)))
        let frame = try decode(#"{"t":"snap","envelope":{"rev":42,"kind":"snap","n":"ha_Fwfr-03T8OAOV","ct":"abc"}}"#)
        guard case .frame(let wsFrame) = frame else {
            Issue.record("expected frame")
            return
        }
        #expect(wsFrame.t == .snap)
    }

    @Test func bearerSocketSendsRoleInHello() async throws {
        let connector = ScriptedWebSocket()
        let socket = BearerWebSocket(writeToken: Data(repeating: 9, count: 32), role: .mac, connector: connector)
        let connection = try await socket.connect()
        try await connection.sendEcho(id: id)
        let sent = await connector.sentText
        #expect(sent == [ContractHello.text(role: .mac), WSControl.echo(id: id)])
        await connection.close()
    }

    @Test func macConnectionAnswersPingWithEchoBeforeHandingItOn() async throws {
        let envelope = Envelope(rev: 1, kind: .snap, n: "ha_Fwfr-03T8OAOV", ct: "abc")
        let scripted = ScriptedWebSocket(incoming: [
            .hello(ContractAnnouncement(contract: 16, minReadable: 3)),
            .ping(id),
            .frame(WSFrame(t: .snap, envelope: envelope)),
        ])
        let socket = BearerWebSocket(writeToken: Data(repeating: 9, count: 32), role: .mac, connector: scripted)
        let connection = EchoingWebSocketConnection(try await socket.connect())

        #expect(try await connection.receiveIncoming() == .hello(ContractAnnouncement(contract: 16, minReadable: 3)))
        #expect(await scripted.sentText == [ContractHello.text(role: .mac)])

        #expect(try await connection.receiveIncoming() == .ping(id))
        #expect(await scripted.sentText == [ContractHello.text(role: .mac), WSControl.echo(id: id)])

        guard case .frame(let frame) = try await connection.receiveIncoming() else {
            Issue.record("expected frame")
            return
        }
        #expect(frame.t == .snap)
        #expect(await scripted.sentText.count == 2)
        await connection.close()
    }

    @Test func macConnectionLeavesPongAndEchoAlone() async throws {
        let scripted = ScriptedWebSocket(incoming: [.pong(id), .echo(id: id, mac: true)])
        let connection = EchoingWebSocketConnection(scripted)
        #expect(try await connection.receiveIncoming() == .pong(id))
        #expect(try await connection.receiveIncoming() == .echo(id: id, mac: true))
        #expect(await scripted.sentText.isEmpty)
    }
}
