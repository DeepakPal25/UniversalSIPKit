import Foundation

/// Initializes the SIP engine endpoint. Must run before any other use case.
public struct InitializeSIPUseCase: Sendable {

    private let engine: SIPEngineProtocol

    public init(engine: SIPEngineProtocol) {
        self.engine = engine
    }

    public func callAsFunction() async throws {
        try await engine.initialize()
    }
}
