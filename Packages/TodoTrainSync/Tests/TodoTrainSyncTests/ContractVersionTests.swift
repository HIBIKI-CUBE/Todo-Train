import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Contract version")
struct ContractVersionTests {
    @Test func constantsMatchVersionJSON() throws {
        let data = try ContractFixtures.data("version.json")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["contract"] as? Int == ContractVersion.contract)
        #expect(json["minReadable"] as? Int == ContractVersion.minReadable)
        #expect(ContractVersion.minReadable <= ContractVersion.contract)
        #expect(ContractVersion.legacy == 3)
    }

    @Test func currentTypesReadEveryFrozenFixtureAtOrAboveMinReadable() throws {
        let fixtures = ContractFixtures.directory.appendingPathComponent("fixtures")
        let versions = try FileManager.default.contentsOfDirectory(
            at: fixtures,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && url.lastPathComponent.range(of: #"^v\d+$"#, options: .regularExpression) != nil
        }
        #expect(!versions.isEmpty)
        var read = 0
        for versionURL in versions {
            let number = try #require(Int(versionURL.lastPathComponent.dropFirst()))
            guard number >= ContractVersion.minReadable else { continue }
            let files = try FileManager.default.contentsOfDirectory(at: versionURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            #expect(!files.isEmpty)
            for file in files {
                let data = try Data(contentsOf: file)
                let name = file.lastPathComponent
                if name.hasPrefix("snap") {
                    _ = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
                } else if name.hasPrefix("cmd") {
                    _ = try WireJSON.decoder().decode(CommandPlaintext.self, from: data)
                } else if name.hasPrefix("ack") {
                    _ = try WireJSON.decoder().decode(AckPlaintext.self, from: data)
                } else if name.hasPrefix("hint") {
                    _ = try WireJSON.decoder().decode(HintPlaintext.self, from: data)
                } else {
                    Issue.record("凍結 fixture の種類が不明: \(name)")
                }
                read += 1
            }
        }
        #expect(read >= 11)
    }

    @Test func missingAnnouncementIsLegacyAndPartialKeysDoNotFailTheSnap() throws {
        let data = try ContractFixtures.data("fixtures/v3/snap.json")
        let legacy = try WireJSON.decoder().decode(SnapPlaintext.self, from: data)
        #expect(legacy.contract == nil)
        #expect(legacy.announcement == .legacyPeer)
        #expect(ContractCompat.evaluate(peer: legacy.announcement).maySendOperations)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["contract"] = "4"
        object["minReadable"] = 3
        let partial = try JSONSerialization.data(withJSONObject: object)
        let decoded = try WireJSON.decoder().decode(SnapPlaintext.self, from: partial)
        #expect(decoded.title == legacy.title)
        #expect(decoded.announcement == .legacyPeer)
    }

    @Test func commandBlockStopsOnlyOutsideTheRange() {
        let local = ContractAnnouncement.current
        #expect(ContractCompat.commandBlock(peer: .legacyPeer, relay: .legacyPeer, side: .iphone) == nil)
        #expect(ContractCompat.evaluate(local: local, peer: ContractAnnouncement(contract: 9, minReadable: 3)) == .peerNewer)
        #expect(ContractCompat.commandBlock(
            peer: ContractAnnouncement(contract: 2, minReadable: 2),
            relay: nil,
            side: .iphone
        ) == ContractCopy.macOlder)
        #expect(ContractCompat.commandBlock(
            peer: ContractAnnouncement(contract: 2, minReadable: 2),
            relay: nil,
            side: .mac
        ) == ContractCopy.iphoneOlder)
        #expect(ContractCompat.commandBlock(
            peer: nil,
            relay: ContractAnnouncement(contract: 2, minReadable: 2),
            side: .mac
        ) == ContractCopy.relayOlder)
        #expect(ContractCompat.commandBlock(peer: nil, relay: nil, side: .mac) == nil)
        #expect(ContractAnnouncement.parseHeader(nil) == .legacyPeer)
        #expect(ContractAnnouncement.parseHeader("5;min=3") == .current)
        #expect(ContractAnnouncement.parseHeader("4;min=3") == ContractAnnouncement(contract: 4, minReadable: 3))
        #expect(ContractAnnouncement.parseHeader("soon") == nil)
    }

    @Test func presentationStaysQuietUntilAPeerArrivesAndSpeaksOnlyOnTheDiagnosticLineWhenInRange() {
        #expect(ContractPresentation.make(peer: nil, relay: nil, side: .iphone) == .quiet)
        #expect(ContractPresentation.make(peer: nil, relay: .current, side: .mac) == .quiet)
        let aligned = ContractPresentation.make(peer: .legacyPeer, relay: .legacyPeer, side: .iphone)
        #expect(aligned.diagnostic == ContractCopy.aligned)
        #expect(aligned.guidance.isEmpty)
        let newer = ContractPresentation.make(
            peer: ContractAnnouncement(contract: 9, minReadable: 3),
            relay: nil,
            side: .mac
        )
        #expect(newer.diagnostic == ContractCopy.aligned)
        #expect(newer.guidance.isEmpty)
    }

    @Test func presentationNamesWhoToUpdateWhenOutsideTheRange() {
        let macOld = ContractPresentation.make(
            peer: ContractAnnouncement(contract: 2, minReadable: 2),
            relay: nil,
            side: .iphone
        )
        #expect(macOld.diagnostic == nil)
        #expect(macOld.guidance == [
            ContractCopy.versions(iphone: ContractVersion.contract, mac: 2),
            ContractCopy.macOlder,
        ])
        let iphoneOld = ContractPresentation.make(
            peer: ContractAnnouncement(contract: 2, minReadable: 2),
            relay: nil,
            side: .mac
        )
        #expect(iphoneOld.guidance == [
            ContractCopy.versions(iphone: 2, mac: ContractVersion.contract),
            ContractCopy.iphoneOlder,
        ])
        let relayOld = ContractPresentation.make(
            peer: nil,
            relay: ContractAnnouncement(contract: 2, minReadable: 2),
            side: .iphone
        )
        #expect(relayOld.guidance == [ContractCopy.relayOlder])
        let selfOld = ContractPresentation.make(
            local: ContractAnnouncement(contract: 3, minReadable: 3),
            peer: ContractAnnouncement(contract: 4, minReadable: 4),
            relay: nil,
            side: .iphone
        )
        #expect(selfOld.guidance == [
            ContractCopy.versions(iphone: 3, mac: 4),
            ContractCopy.iphoneOlder,
        ])
    }
}
