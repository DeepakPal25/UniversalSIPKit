import Foundation

/// Places a call on hold or resumes it.
public struct HoldCallUseCase: Sendable {

    private let engine: SIPEngineProtocol

    public init(engine: SIPEngineProtocol) {
        self.engine = engine
    }

    public func callAsFunction(callID: UUID, held: Bool) async throws {
        try await engine.setHeld(callID: callID, held: held)
    }
}
