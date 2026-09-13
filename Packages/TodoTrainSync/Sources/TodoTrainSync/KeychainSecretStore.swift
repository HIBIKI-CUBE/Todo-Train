#if canImport(Security)
import Foundation
import Security

public struct KeychainSecretStore: SecretStoring {
    public var service: String
    public var account: String

    public init(
        service: String = "dev.hibiki-cube.Todo-train.companion",
        account: String = "pairing"
    ) {
        self.service = service
        self.account = account
    }

    public func load() throws -> PairingSecrets? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SyncError.notPaired
        }
        return try JSONDecoder().decode(PairingSecrets.self, from: data)
    }

    public func save(_ secrets: PairingSecrets) throws {
        let data = try JSONEncoder().encode(secrets)
        try delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SyncError.notPaired }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SyncError.notPaired
        }
    }
}
#endif
