import Foundation
import SIPDomain

/// Coordinates secure credential persistence and provider registration.
///
/// If registration fails after credentials were persisted, the previously
/// stored credentials are rolled back so the store never retains secrets for
/// an account that is not actually registered.
public actor AccountRepositoryImpl: AccountRepositoryProtocol {

    private let provider: VoiceProviderProtocol
    private let credentialStore: CredentialStoreProtocol
    private var accounts: [UUID: VoiceAccount] = [:]

    public init(
        provider: VoiceProviderProtocol,
        credentialStore: CredentialStoreProtocol
    ) {
        self.provider = provider
        self.credentialStore = credentialStore
    }

    public func addAccount(
        _ account: VoiceAccount,
        credential: ProviderCredential
    ) async throws {
        try await credentialStore.save(credential, for: account.id)

        do {
            try await provider.register(account: account, credential: credential)
        } catch {
            // Roll back credential persistence so we never retain secrets for
            // an account that failed to register.
            try? await credentialStore.delete(for: account.id)
            throw error
        }

        accounts[account.id] = account
    }

    public func removeAccount(id: UUID) async throws {
        guard accounts[id] != nil else {
            throw SIPError.accountNotFound
        }

        try await provider.unregister(accountID: id)
        try? await credentialStore.delete(for: id)
        accounts[id] = nil
    }

    public func registeredAccounts() async -> [VoiceAccount] {
        Array(accounts.values)
    }
}
