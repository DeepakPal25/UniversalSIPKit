import Foundation

/// Registers / connects an account with its provider.
public struct RegisterAccountUseCase: Sendable {

    private let repository: AccountRepositoryProtocol

    public init(repository: AccountRepositoryProtocol) {
        self.repository = repository
    }

    public func callAsFunction(
        account: VoiceAccount,
        credential: ProviderCredential
    ) async throws {
        guard !account.identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SIPError.invalidConfiguration
        }
        guard !credential.isEmpty else {
            throw SIPError.invalidCredentials
        }
        try await repository.addAccount(account, credential: credential)
    }
}
