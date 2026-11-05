import Foundation

/// Accepts an incoming call.
public struct AnswerCallUseCase: Sendable {

    private let engine: SIPEngineProtocol

    public init(engine: SIPEngineProtocol) {
        self.engine = engine
    }

    public func callAsFunction(callID: UUID) async throws {
        try await engine.answerCall(callID: callID)
    }
}
