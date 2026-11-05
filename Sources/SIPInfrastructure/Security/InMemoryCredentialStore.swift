import Foundation
import SIPDomain

/// A non-persistent credential store for tests and previews.
///
/// Never use this in production — it keeps secrets in process memory only and
/// provides no protection. Use ``KeychainCredentialStore`` on device.
public actor InMemoryCredentialStore: CredentialStoreProtocol {

    private var store: [UUID: ProviderCredential] = [:]

    public init() {}

    public func save(_ credential: ProviderCredential, for accountID: UUID) async throws {
        store[accountID] = credential
    }

    public func credential(for accountID: UUID) async throws -> ProviderCredential? {
        store[accountID]
    }

    public func delete(for accountID: UUID) async throws {
        store[accountID] = nil
    }
}
