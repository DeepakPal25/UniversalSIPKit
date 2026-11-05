import Foundation

/// Coordinates account registration and secure credential persistence across
/// any provider.
public protocol AccountRepositoryProtocol: Sendable {

    func addAccount(_ account: VoiceAccount, credential: ProviderCredential) async throws

    func removeAccount(id: UUID) async throws

    func registeredAccounts() async -> [VoiceAccount]
}

/// Backwards-compatible alias.
public typealias SIPAccountRepositoryProtocol = AccountRepositoryProtocol
