import Foundation
import SIPDomain

/// Non-SIP ``VoiceProviderProtocol`` backed by the Twilio Voice iOS SDK.
///
/// This proves the engine seam is genuinely provider-neutral: Twilio does not
/// use SIP registration. Instead the host's backend mints a short-lived access
/// token (carried as ``ProviderCredential/accessToken(_:)``), and the SDK
/// `register` step maps to Twilio's push-credential registration while
/// `makeCall` maps to `TwilioVoiceSDK.connect(accessToken:)`.
///
/// This is a skeleton. The concrete implementation requires adding the
/// `TwilioVoice` dependency (not vendored here, since it is a closed-source
/// binary with its own licensing). Until then every operation reports
/// ``SIPError/unsupportedOperation``.
///
/// Implementation notes for when the Twilio SDK is added:
/// - `register`: call `TwilioVoiceSDK.register(accessToken:deviceToken:)` using
///   the VoIP push token from ``VoIPPushManager``.
/// - Incoming pushes: `TwilioVoiceSDK.handleNotification(_:delegate:)` →
///   emit ``SIPCallEvent/incomingCall(_:)``.
/// - `makeCall`: `TwilioVoiceSDK.connect(options:delegate:)`.
/// - Bridge `CallDelegate`/`CallInvite` callbacks into ``SIPCallEvent`` via
///   ``EventBroadcaster``, mapping Twilio errors into ``SIPError``.
public actor TwilioVoiceProvider: VoiceProviderProtocol {

    public nonisolated let providerID = "twilio"

    private let broadcaster = EventBroadcaster()

    public init() {}

    public func initialize() async throws { throw SIPError.unsupportedOperation }
    public func shutdown() async throws { await broadcaster.finishAll() }
    public func events() async -> AsyncStream<SIPCallEvent> { await broadcaster.subscribe() }

    public func register(account: VoiceAccount, credential: ProviderCredential) async throws {
        guard case .accessToken = credential else {
            // Twilio authenticates with an access token, not SIP credentials.
            throw SIPError.invalidCredentials
        }
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
