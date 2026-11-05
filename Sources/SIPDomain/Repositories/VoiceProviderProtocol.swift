import Foundation

/// The provider-neutral abstraction over a concrete calling engine.
///
/// A provider may be a SIP engine (Baresip, PJSIP) or a non-SIP vendor SDK
/// (Twilio, Vonage, Agora). The Domain layer depends only on this protocol;
/// concrete providers live in Infrastructure and must never leak
/// provider-specific types across this boundary. Implementations are expected
/// to serialize access to internal state (e.g. by being an `actor`), because
/// underlying C APIs and vendor SDKs are not guaranteed to be concurrency-safe.
///
/// Call verbs (`makeCall`, `answerCall`, …) are universal. Only `register` /
/// `unregister` differ in meaning per provider: for SIP it is a REGISTER, for a
/// token vendor it is "prepare this identity for making/receiving calls".
public protocol VoiceProviderProtocol: Sendable {

    /// Stable identifier for the provider, e.g. `sip.baresip`, `twilio`.
    var providerID: String { get }

    /// Initializes the provider. Must be called once before any other operation.
    func initialize() async throws

    /// Shuts the provider down and releases all resources.
    func shutdown() async throws

    /// A stream of events. Each call returns an independent stream;
    /// implementations must broadcast events to all active subscribers.
    func events() async -> AsyncStream<SIPCallEvent>

    /// Registers / connects an account using provider-neutral credentials.
    func register(account: VoiceAccount, credential: ProviderCredential) async throws

    /// Unregisters / disconnects an account.
    func unregister(accountID: UUID) async throws

    @discardableResult
    func makeCall(accountID: UUID, destination: String) async throws -> SIPCall

    func answerCall(callID: UUID) async throws

    func rejectCall(callID: UUID) async throws

    func endCall(callID: UUID) async throws

    func setMuted(callID: UUID, muted: Bool) async throws

    func setHeld(callID: UUID, held: Bool) async throws

    /// The current snapshot of all known calls.
    func currentCalls() async -> [SIPCall]
}

/// Backwards-compatible alias. SIP engines are one kind of voice provider.
public typealias SIPEngineProtocol = VoiceProviderProtocol
