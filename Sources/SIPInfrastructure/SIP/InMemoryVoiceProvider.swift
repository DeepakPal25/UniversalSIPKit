import Foundation
import SIPDomain

/// A fully in-memory ``VoiceProviderProtocol`` implementation.
///
/// It performs no real signaling or media. It simulates registration and
/// call-state transitions so the full SDK stack can be exercised in demos and
/// tests before a real provider (Baresip, PJSIP, Twilio) is wired in. It also
/// documents the event contract a real provider must honor (no events after a
/// terminal call event, etc.).
///
/// The `providerID` is configurable so the same simulator can stand in for a
/// SIP provider or a token-based vendor in tests.
public actor InMemoryVoiceProvider: VoiceProviderProtocol {

    public nonisolated let providerID: String

    private let broadcaster = EventBroadcaster()
    private var isInitialized = false
    private var registeredAccounts: Set<UUID> = []
    private var calls: [UUID: SIPCall] = [:]

    public init(providerID: String = "sip.inmemory") {
        self.providerID = providerID
    }

    public func initialize() async throws {
        isInitialized = true
    }

    public func shutdown() async throws {
        for id in calls.keys {
            calls[id] = calls[id]?.with(state: .ended)
            await broadcaster.emit(.callEnded(callID: id))
        }
        calls.removeAll()
        registeredAccounts.removeAll()
        isInitialized = false
        await broadcaster.finishAll()
    }

    public func events() async -> AsyncStream<SIPCallEvent> {
        await broadcaster.subscribe()
    }

    public func register(account: VoiceAccount, credential: ProviderCredential) async throws {
        try ensureInitialized()
        await broadcaster.emit(.registrationChanged(accountID: account.id, state: .registering))
        registeredAccounts.insert(account.id)
        await broadcaster.emit(.registrationChanged(accountID: account.id, state: .registered))
    }

    public func unregister(accountID: UUID) async throws {
        try ensureInitialized()
        registeredAccounts.remove(accountID)
        await broadcaster.emit(.registrationChanged(accountID: accountID, state: .unregistered))
    }

    @discardableResult
    public func makeCall(accountID: UUID, destination: String) async throws -> SIPCall {
        try ensureInitialized()
        guard registeredAccounts.contains(accountID) else {
            throw SIPError.accountNotRegistered
        }

        let call = SIPCall(
            id: UUID(),
            accountID: accountID,
            remoteNumber: destination,
            isIncoming: false,
            state: .connecting
        )
        calls[call.id] = call
        await broadcaster.emit(.outgoingCallStarted(call))

        // Simulate the call reaching the connected state.
        transition(call.id, to: .ringing)
        transition(call.id, to: .connected)
        await emitConnectedIfNeeded(call.id)
        return calls[call.id] ?? call
    }

    public func answerCall(callID: UUID) async throws {
        try ensureInitialized()
        guard let call = calls[callID] else { throw SIPError.callNotFound }
        guard call.isIncoming else { throw SIPError.unsupportedOperation }
        transition(callID, to: .connected)
        await emitConnectedIfNeeded(callID)
    }

    public func rejectCall(callID: UUID) async throws {
        try ensureInitialized()
        guard calls[callID] != nil else { throw SIPError.callNotFound }
        transition(callID, to: .ended)
        calls[callID] = nil
        await broadcaster.emit(.callEnded(callID: callID))
    }

    public func endCall(callID: UUID) async throws {
        try ensureInitialized()
        guard calls[callID] != nil else { throw SIPError.callNotFound }
        transition(callID, to: .ended)
        calls[callID] = nil
        await broadcaster.emit(.callEnded(callID: callID))
    }

    public func setMuted(callID: UUID, muted: Bool) async throws {
        try ensureInitialized()
        guard let call = calls[callID] else { throw SIPError.callNotFound }
        let updated = call.with(isMuted: muted)
        calls[callID] = updated
        await broadcaster.emit(.callStateChanged(updated))
    }

    public func setHeld(callID: UUID, held: Bool) async throws {
        try ensureInitialized()
        guard let call = calls[callID] else { throw SIPError.callNotFound }
        let updated = call.with(state: held ? .onHold : .connected, isOnHold: held)
        calls[callID] = updated
        await broadcaster.emit(.callStateChanged(updated))
    }

    public func currentCalls() async -> [SIPCall] {
        Array(calls.values)
    }

    // MARK: - Simulation helpers

    /// Simulates receipt of an inbound call. Intended for tests and demos.
    public func simulateIncomingCall(
        accountID: UUID,
        from remoteNumber: String
    ) async -> SIPCall {
        let call = SIPCall(
            id: UUID(),
            accountID: accountID,
            remoteNumber: remoteNumber,
            isIncoming: true,
            state: .incoming
        )
        calls[call.id] = call
        await broadcaster.emit(.incomingCall(call))
        return call
    }

    private func ensureInitialized() throws {
        guard isInitialized else { throw SIPError.notInitialized }
    }

    private func transition(_ callID: UUID, to state: SIPCallState) {
        guard let call = calls[callID] else { return }
        let updated = call.with(state: state)
        calls[callID] = updated
    }

    private func emitConnectedIfNeeded(_ callID: UUID) async {
        guard let call = calls[callID], call.state == .connected else { return }
        await broadcaster.emit(.callStateChanged(call))
        await broadcaster.emit(.callConnected(callID: callID))
    }
}
