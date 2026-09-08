import Foundation

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    static func decode(_ string: String) throws -> Data {
        var encoded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - encoded.count % 4) % 4
        encoded.append(String(repeating: "=", count: pad))
        guard let data = Data(base64Encoded: encoded) else {
            throw SyncError.invalidBase64URL
        }
        return data
    }
}
