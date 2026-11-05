import Foundation

/// Rejects an incoming call.
public struct RejectCallUseCase: Sendable {

    private let engine: SIPEngineProtocol

    public init(engine: SIPEngineProtocol) {
        self.engine = engine
    }

    public func callAsFunction(callID: UUID) async throws {
        try await engine.rejectCall(callID: callID)
    }
}
