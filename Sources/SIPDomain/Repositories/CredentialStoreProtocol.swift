import Foundation

/// A protected store for provider credentials.
///
/// Production implementations must use the platform Keychain and must never
/// persist secrets to insecure storage such as `UserDefaults`. Note that
/// token-based providers typically use short-lived access tokens fetched on
/// demand; persisting those is optional and often unnecessary.
public protocol CredentialStoreProtocol: Sendable {

    func save(_ credential: ProviderCredential, for accountID: UUID) async throws

    func credential(for accountID: UUID) async throws -> ProviderCredential?

    func delete(for accountID: UUID) async throws
}
