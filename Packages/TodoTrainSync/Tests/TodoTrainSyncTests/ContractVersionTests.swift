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
}
