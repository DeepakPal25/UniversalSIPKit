import Foundation

/// Observes the stream of registration and call events.
public struct ObserveCallEventsUseCase: Sendable {

    private let repository: CallRepositoryProtocol

    public init(repository: CallRepositoryProtocol) {
        self.repository = repository
    }

    public func callAsFunction() async -> AsyncStream<SIPCallEvent> {
        await repository.observeCallEvents()
    }
}
