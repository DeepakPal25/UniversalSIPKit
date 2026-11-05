import Foundation

/// Starts an outgoing call, validating the destination first.
public struct MakeCallUseCase: Sendable {

    private let engine: SIPEngineProtocol

    public init(engine: SIPEngineProtocol) {
        self.engine = engine
    }

    @discardableResult
    public func callAsFunction(
        accountID: UUID,
        destination: String
    ) async throws -> SIPCall {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SIPError.invalidDestination
        }
        return try await engine.makeCall(accountID: accountID, destination: trimmed)
    }
}
