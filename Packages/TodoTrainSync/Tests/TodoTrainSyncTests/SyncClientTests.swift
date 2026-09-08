import Foundation
import Testing
@testable import TodoTrainSync

@Suite("HTTP client and pairing flow")
struct SyncClientTests {
    let base = URL(string: "http://127.0.0.1:8787")!

    @Test func createOfferAndPutSnapUseContractPaths() async throws {
        let transport = ScriptedHTTPTransport([
            .init(
                status: 201,
                json: #"{"offerId":"b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb","pairingId":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea","expiresAt":1768000120}"#
            ),
            .init(status: 200, json: #"{"rev":42}"#),
        ])
        let client = SyncHTTPClient(baseURL: base, transport: transport, writeToken: Data(repeating: 7, count: 32))
        let offer = try await client.createOffer(x: Data(repeating: 1, count: 32))
        #expect(offer.offerId == UUID(uuidString: "b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb"))
        #expect(offer.pairingId == UUID(uuidString: "a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"))

        let envelope = Envelope(rev: 42, kind: .snap, n: "ha_Fwfr-03T8OAOV", ct: "abc")
        let put = try await client.putSnap(envelope)
        #expect(put.rev == 42)

        let requests = await transport.requests
        #expect(requests[0].method == "POST")
        #expect(requests[0].path == "/v1/offers")
        #expect(requests[0].headers["Authorization"] == nil)
        #expect(requests[1].method == "PUT")
        #expect(requests[1].path == "/v1/snap")
        #expect(requests[1].headers["Authorization"]?.hasPrefix("Bearer ") == true)
    }

    @Test func iphonePairingMachineBindThenLA() async throws {
        let transport = ScriptedHTTPTransport([
            .init(
                status: 201,
                json: #"{"offerId":"b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb","pairingId":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea","expiresAt":1768000120}"#
            ),
            .init(status: 200, json: #"{"bound":false}"#),
            .init(
                status: 200,
                json: #"{"bound":true,"pairingId":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea","s":"c1c2c3c4-d1d2-4e3e-8f4f-a5a6a7a8a9aa","x":"6cUEjnLPwR0PtWYzHUVx7rfJ4kbso5tubUYqdeFHIRI","y":"UgKyT75SOaUjcnm8rdNOZvC3qC3oVkNtdt-WlgkO9rI"}"#
            ),
            .init(status: 200, json: #"{"confirmed":true,"pairingId":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"}"#),
            .init(status: 200, json: #"{"pairingId":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"}"#),
        ])
        let client = SyncHTTPClient(baseURL: base, transport: transport)
        let store = InMemorySecretStore()
        let flow = PairingFlow(role: .iphone, client: client, secrets: store, localAuth: ImmediateLocalAuth())

        let qr = try await flow.presentQR()
        if case .iphone(let pairingId, let offerId, let x) = qr {
            #expect(pairingId == UUID(uuidString: "a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"))
            #expect(offerId == UUID(uuidString: "b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb"))
            #expect(x.count == 32)
        } else {
            Issue.record("iPhone QR")
        }
        let phase1 = await flow.phase
        if case .presentingQR = phase1 {} else { Issue.record("expected presentingQR") }

        let macURL = "todotrain://pair-mac?s=c1c2c3c4-d1d2-4e3e-8f4f-a5a6a7a8a9aa&y=UgKyT75SOaUjcnm8rdNOZvC3qC3oVkNtdt-WlgkO9rI"
        let firstBind = try await flow.ingestOptical(macURL)
        #expect(!firstBind.bound)
        let phase2 = await flow.phase
        #expect(phase2 == .binding)

        let secondBind = try await flow.refreshBind()
        #expect(secondBind.bound)
        let phase3 = await flow.phase
        #expect(phase3 == .awaitingLocalAuth)

        try await flow.authenticateAndConfirm()
        let phase4 = await flow.phase
        #expect(phase4 == .established)
        let saved = try store.load()
        #expect(saved?.pairingId == UUID(uuidString: "a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"))
        #expect(saved?.masterKey.count == 32)
        #expect(saved?.writeToken.count == 32)

        let requests = await transport.requests
        #expect(requests.map(\.path) == [
            "/v1/offers",
            "/v1/offers/b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb/bind",
            "/v1/offers/b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb/bind",
            "/v1/offers/b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb/confirm-iphone",
            "/v1/pairings/a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea",
        ])
        #expect(requests[3].body.flatMap { String(data: $0, encoding: .utf8) }?.contains("hmac") == true)
    }

    @Test func oneSidedOpticalDoesNotAuthenticate() async throws {
        let transport = ScriptedHTTPTransport([
            .init(
                status: 201,
                json: #"{"offerId":"b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb","pairingId":"a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea","expiresAt":1768000120}"#
            ),
        ])
        let flow = PairingFlow(
            role: .iphone,
            client: SyncHTTPClient(baseURL: base, transport: transport),
            secrets: InMemorySecretStore()
        )
        _ = try await flow.presentQR()
        await #expect(throws: SyncError.pairingNotBound) {
            try await flow.authenticateAndConfirm()
        }
    }

    @Test func websocketFakeYieldsContractFrame() async throws {
        let envelope = Envelope(rev: 42, kind: .snap, n: "ha_Fwfr-03T8OAOV", ct: "abc")
        let connector = ScriptedWebSocket(frames: [WSFrame(t: .snap, envelope: envelope)])
        let socket = BearerWebSocket(writeToken: Data(repeating: 9, count: 32), connector: connector)
        let connection = try await socket.connect()
        let frame = try await connection.receive()
        #expect(frame.t == .snap)
        #expect(frame.envelope.rev == 42)
        await connection.close()
    }
}
