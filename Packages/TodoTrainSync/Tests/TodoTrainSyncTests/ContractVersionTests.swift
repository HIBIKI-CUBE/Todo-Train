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
}
