import Foundation

/// Terminates an active call.
public struct EndCallUseCase: Sendable {

    private let engine: SIPEngineProtocol

    public init(engine: SIPEngineProtocol) {
        self.engine = engine
    }

    public func callAsFunction(callID: UUID) async throws {
        try await engine.endCall(callID: callID)
    }
}
