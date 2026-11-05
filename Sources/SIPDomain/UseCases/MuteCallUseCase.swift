import Foundation

/// Mutes or unmutes the microphone for a call.
public struct MuteCallUseCase: Sendable {

    private let engine: SIPEngineProtocol

    public init(engine: SIPEngineProtocol) {
        self.engine = engine
    }

    public func callAsFunction(callID: UUID, muted: Bool) async throws {
        try await engine.setMuted(callID: callID, muted: muted)
    }
}
