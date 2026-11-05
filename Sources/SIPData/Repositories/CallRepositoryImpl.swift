import Foundation
import SIPDomain

/// Exposes engine call events and current call state to the Domain layer.
public struct CallRepositoryImpl: CallRepositoryProtocol {

    private let provider: VoiceProviderProtocol

    public init(provider: VoiceProviderProtocol) {
        self.provider = provider
    }

    public func observeCallEvents() async -> AsyncStream<SIPCallEvent> {
        await provider.events()
    }

    public func currentCalls() async -> [SIPCall] {
        await provider.currentCalls()
    }
}
