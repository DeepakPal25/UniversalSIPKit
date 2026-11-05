import Foundation
import SIPDomain

/// Fans a single source of ``SIPCallEvent`` values out to any number of
/// independent `AsyncStream` subscribers.
///
/// Each call to ``subscribe()`` returns its own stream. Yields are delivered to
/// every active subscriber in registration order, which preserves event
/// ordering across all observers.
public actor EventBroadcaster {

    private var continuations: [UUID: AsyncStream<SIPCallEvent>.Continuation] = [:]

    public init() {}

    /// Creates a new subscription stream. The subscription is removed
    /// automatically when the consumer stops iterating.
    public func subscribe() -> AsyncStream<SIPCallEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    /// Delivers an event to every active subscriber.
    public func emit(_ event: SIPCallEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Finishes all subscriber streams.
    public func finishAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}
