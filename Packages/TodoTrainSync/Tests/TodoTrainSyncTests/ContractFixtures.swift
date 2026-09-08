import Foundation

enum ContractFixtures {
    static var directory: URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("sync/contract")
    }

    static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(relativePath))
    }

    static func jsonObject(_ relativePath: String) throws -> NSDictionary {
        let data = try data(relativePath)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? NSDictionary else {
            throw NSError(domain: "ContractFixtures", code: 1)
        }
        return dictionary
    }
}
