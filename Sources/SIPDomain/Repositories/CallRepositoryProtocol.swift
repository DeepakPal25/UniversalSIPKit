import Foundation

/// Provides observation of call events and access to current call state.
public protocol CallRepositoryProtocol: Sendable {

    func observeCallEvents() async -> AsyncStream<SIPCallEvent>

    func currentCalls() async -> [SIPCall]
}
