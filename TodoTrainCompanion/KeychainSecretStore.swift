import Foundation
import Security
import TodoTrainSync

struct KeychainSecretStore: SecretStoring {
    var service: String
    var account: String

    init(
        service: String = "dev.hibiki-cube.Todo-train.companion",
        account: String = "pairing"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> PairingSecrets? {
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

    func save(_ secrets: PairingSecrets) throws {
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

    func delete() throws {
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
