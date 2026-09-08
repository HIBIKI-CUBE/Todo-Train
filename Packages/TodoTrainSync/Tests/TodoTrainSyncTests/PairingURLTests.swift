import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Pairing URL")
struct PairingURLTests {
    @Test func goldenExamplesParseAndRebuild() throws {
        let text = String(data: try ContractFixtures.data("pairing-url.examples.txt"), encoding: .utf8)!
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        #expect(lines.count == 2)

        let iphone = try PairingURL.parse(lines[0])
        let mac = try PairingURL.parse(lines[1])
        #expect(iphone.encoded == lines[0])
        #expect(mac.encoded == lines[1])

        if case .iphone(let pairingId, let offerId, let x) = iphone {
            #expect(pairingId == UUID(uuidString: "a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"))
            #expect(offerId == UUID(uuidString: "b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb"))
            #expect(x.count == 32)
            #expect(Base64URL.encode(x) == "6cUEjnLPwR0PtWYzHUVx7rfJ4kbso5tubUYqdeFHIRI")
        } else {
            Issue.record("expected iphone URL")
        }

        if case .mac(let session, let y) = mac {
            #expect(session == UUID(uuidString: "c1c2c3c4-d1d2-4e3e-8f4f-a5a6a7a8a9aa"))
            #expect(y.count == 32)
            #expect(Base64URL.encode(y) == "UgKyT75SOaUjcnm8rdNOZvC3qC3oVkNtdt-WlgkO9rI")
        } else {
            Issue.record("expected mac URL")
        }
    }

    @Test func parserAcceptsReorderedQuery() throws {
        let reordered = "todotrain://pair?x=6cUEjnLPwR0PtWYzHUVx7rfJ4kbso5tubUYqdeFHIRI&o=b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb&p=a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea"
        let parsed = try PairingURL.parse(reordered)
        #expect(parsed.encoded.hasPrefix("todotrain://pair?p="))
        #expect(parsed.encoded.contains("&o="))
        #expect(parsed.encoded.contains("&x="))
    }

    @Test func extraQueryIsRejected() {
        let extra = "todotrain://pair?p=a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea&o=b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb&x=6cUEjnLPwR0PtWYzHUVx7rfJ4kbso5tubUYqdeFHIRI&k=1"
        #expect(throws: SyncError.invalidPairingURL) {
            _ = try PairingURL.parse(extra)
        }
    }
}
