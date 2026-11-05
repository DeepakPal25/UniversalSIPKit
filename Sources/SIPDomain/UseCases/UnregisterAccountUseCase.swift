import Foundation

/// Removes a SIP account's registration and deletes its stored credentials.
public struct UnregisterAccountUseCase: Sendable {

    private let repository: SIPAccountRepositoryProtocol

    public init(repository: SIPAccountRepositoryProtocol) {
        self.repository = repository
    }

    public func callAsFunction(accountID: UUID) async throws {
        try await repository.removeAccount(id: accountID)
    }
}
