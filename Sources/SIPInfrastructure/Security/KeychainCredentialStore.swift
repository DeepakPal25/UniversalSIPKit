import Foundation
import SIPDomain
import Security

/// A ``CredentialStoreProtocol`` backed by the platform Keychain.
///
/// Credentials are serialized to JSON and stored as a generic password item
/// keyed by the account identifier. Items are protected with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so they are available to
/// background VoIP pushes but never migrate off the device.
public actor KeychainCredentialStore: CredentialStoreProtocol {

    private let service: String

    public init(service: String = "com.universalsipkit.credentials") {
        self.service = service
    }

    public func save(_ credential: ProviderCredential, for accountID: UUID) async throws {
        let data = try JSONEncoder().encode(credential)

        // Replace any existing item for this account.
        try delete(for: accountID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SIPError.internalError
        }
    }

    public func credential(for accountID: UUID) async throws -> ProviderCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SIPError.internalError
        }

        return try JSONDecoder().decode(ProviderCredential.self, from: data)
    }

    public func delete(for accountID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SIPError.internalError
        }
    }
}
