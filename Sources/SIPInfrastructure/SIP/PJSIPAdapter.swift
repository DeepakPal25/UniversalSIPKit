import Foundation
import SIPDomain

/// SIP ``VoiceProviderProtocol`` backed by PJSIP.
///
/// This is an architectural skeleton. The concrete implementation requires the
/// PJSIP C library vendored as an XCFramework and bridged through a dedicated
/// C/Objective-C interop target. Until those binaries are present, every
/// operation reports ``SIPError/unsupportedOperation`` so callers fail fast and
/// tests/demos can fall back to ``InMemoryVoiceProvider``.
///
/// Implementation notes for when PJSIP is wired in:
/// - Keep this an `actor`; PJSIP C APIs are not safe to call concurrently.
/// - Convert PJSIP callbacks into ``SIPCallEvent`` via ``EventBroadcaster``.
/// - Never expose raw C pointers or PJSIP types across this boundary.
/// - Map PJSIP status codes into ``SIPError`` cases.
/// - Read SIP domain/port/transport from `VoiceAccount.settings`.
public actor PJSIPAdapter: VoiceProviderProtocol {

    public nonisolated let providerID = "sip.pjsip"

    private let broadcaster = EventBroadcaster()

    public init() {}

    public func initialize() async throws { throw SIPError.unsupportedOperation }
    public func shutdown() async throws { await broadcaster.finishAll() }
    public func events() async -> AsyncStream<SIPCallEvent> { await broadcaster.subscribe() }

    public func register(account: VoiceAccount, credential: ProviderCredential) async throws {
        throw SIPError.unsupportedOperation
    }
    public func unregister(accountID: UUID) async throws { throw SIPError.unsupportedOperation }

    @discardableResult
    public func makeCall(accountID: UUID, destination: String) async throws -> SIPCall {
        throw SIPError.unsupportedOperation
    }
    public func answerCall(callID: UUID) async throws { throw SIPError.unsupportedOperation }
    public func rejectCall(callID: UUID) async throws { throw SIPError.unsupportedOperation }
    public func endCall(callID: UUID) async throws { throw SIPError.unsupportedOperation }
    public func setMuted(callID: UUID, muted: Bool) async throws { throw SIPError.unsupportedOperation }
    public func setHeld(callID: UUID, held: Bool) async throws { throw SIPError.unsupportedOperation }
    public func currentCalls() async -> [SIPCall] { [] }
}
