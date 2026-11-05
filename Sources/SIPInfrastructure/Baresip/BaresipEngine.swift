import Foundation
import SIPDomain
import BaresipBridge

/// SIP ``VoiceProviderProtocol`` backed by libre/baresip through
/// ``BaresipBridge``.
///
/// Until the Baresip XCFramework is linked, the bridge compiles as a stub and
/// every C call returns `ENOTAVAIL`, which this actor maps to
/// ``SIPError/unsupportedOperation`` — so callers fail fast and fall back to
/// another provider. The Swift control flow below is the real one; only the
/// C implementations are pending.
///
/// Concurrency: all engine state is actor-isolated. baresip callbacks arrive on
/// an engine thread via a `@convention(c)` trampoline, which hops back onto this
/// actor's ``BaresipEventBridge`` before touching any state.
public actor BaresipEngine: VoiceProviderProtocol {

    public nonisolated let providerID = "sip.baresip"

    private let bridge = BaresipEventBridge()
    private var aorByAccount: [UUID: String] = [:]
    private var isInitialized = false

    public init() {}

    /// Whether this build actually links baresip (vs. the stub).
    public nonisolated var isEngineAvailable: Bool {
        usk_baresip_is_available() != 0
    }

    public func initialize() async throws {
        let ctx = Unmanaged.passUnretained(bridge).toOpaque()
        usk_baresip_set_event_handler(baresipEventTrampoline, ctx)
        try check(usk_baresip_init())
        isInitialized = true
    }

    public func shutdown() async throws {
        usk_baresip_set_event_handler(nil, nil)
        _ = usk_baresip_shutdown()
        isInitialized = false
    }

    public func events() async -> AsyncStream<SIPCallEvent> {
        await bridge.subscribe()
    }

    public func register(account: VoiceAccount, credential: ProviderCredential) async throws {
        try ensureInitialized()
        guard case .sip(let creds) = credential else {
            // baresip is a SIP engine; it only accepts SIP credentials.
            throw SIPError.invalidCredentials
        }
        guard let domain = account.settings[VoiceAccount.SettingKey.domain], !domain.isEmpty else {
            throw SIPError.invalidConfiguration
        }
        let transport = account.settings[VoiceAccount.SettingKey.transport] ?? SIPTransport.udp.rawValue
        let aor = "sip:\(account.identity)@\(domain)"

        try check(usk_baresip_register(aor, creds.authName, creds.password, transport))
        aorByAccount[account.id] = aor
        await bridge.register(aor: aor, accountID: account.id)
    }

    public func unregister(accountID: UUID) async throws {
        try ensureInitialized()
        guard let aor = aorByAccount[accountID] else { throw SIPError.accountNotFound }
        try check(usk_baresip_unregister(aor))
        aorByAccount[accountID] = nil
        await bridge.unregister(aor: aor)
    }

    @discardableResult
    public func makeCall(accountID: UUID, destination: String) async throws -> SIPCall {
        try ensureInitialized()
        guard let aor = aorByAccount[accountID] else { throw SIPError.accountNotRegistered }

        var buffer = [CChar](repeating: 0, count: 256)
        let status = buffer.withUnsafeMutableBufferPointer {
            usk_baresip_make_call(aor, destination, $0.baseAddress, Int32($0.count))
        }
        try check(status)

        let engineCallID = buffer.withUnsafeBufferPointer { ptr -> String in
            guard let base = ptr.baseAddress else { return "" }
            return String(cString: base)
        }
        return await bridge.registerOutgoing(
            engineCallID: engineCallID,
            accountID: accountID,
            destination: destination
        )
    }

    public func answerCall(callID: UUID) async throws {
        try check(usk_baresip_answer(try await engineID(callID)))
    }

    public func rejectCall(callID: UUID) async throws {
        try check(usk_baresip_hangup(try await engineID(callID)))
    }

    public func endCall(callID: UUID) async throws {
        try check(usk_baresip_hangup(try await engineID(callID)))
    }

    public func setMuted(callID: UUID, muted: Bool) async throws {
        try check(usk_baresip_set_mute(try await engineID(callID), muted ? 1 : 0))
    }

    public func setHeld(callID: UUID, held: Bool) async throws {
        try check(usk_baresip_set_hold(try await engineID(callID), held ? 1 : 0))
    }

    public func currentCalls() async -> [SIPCall] {
        await bridge.currentCalls()
    }

    // MARK: - CallKit audio coordination
    //
    // Call these from CXProviderDelegate's didActivate / didDeactivate so
    // baresip drives audio only against CallKit's AVAudioSession, never on its
    // own. This is the integration the PoC must validate.

    public func startAudio(callID: UUID) async throws {
        try check(usk_baresip_audio_start(try await engineID(callID)))
    }

    public func stopAudio(callID: UUID) async throws {
        try check(usk_baresip_audio_stop(try await engineID(callID)))
    }

    // MARK: - Helpers

    private func ensureInitialized() throws {
        guard isInitialized else { throw SIPError.notInitialized }
    }

    private func engineID(_ callID: UUID) async throws -> String {
        guard let engineCallID = await bridge.engineCallID(for: callID) else {
            throw SIPError.callNotFound
        }
        return engineCallID
    }

    private func check(_ status: usk_baresip_status) throws {
        switch status {
        case USK_BARESIP_OK: return
        case USK_BARESIP_ENOTAVAIL: throw SIPError.unsupportedOperation
        case USK_BARESIP_EINVAL: throw SIPError.invalidConfiguration
        case USK_BARESIP_EAUTH: throw SIPError.authenticationFailed
        case USK_BARESIP_EREG: throw SIPError.registrationFailed
        case USK_BARESIP_ECALL: throw SIPError.callFailed
        case USK_BARESIP_ENOTFOUND: throw SIPError.callNotFound
        default: throw SIPError.internalError
        }
    }
}

/// SIP engines are one kind of voice provider; keep the historic name usable.
public typealias BaresipAdapter = BaresipEngine

// MARK: - C event trampoline
//
// A non-capturing `@convention(c)` function is the only thing baresip can call
// back into. It reconstructs the bridge from the opaque context, copies the C
// strings into Swift values, and hops onto the bridge actor.

private func baresipEventTrampoline(
    _ ctx: UnsafeMutableRawPointer?,
    _ event: usk_baresip_event,
    _ aor: UnsafePointer<CChar>?,
    _ callID: UnsafePointer<CChar>?,
    _ peer: UnsafePointer<CChar>?,
    _ code: Int32
) {
    guard let ctx else { return }
    let bridge = Unmanaged<BaresipEventBridge>.fromOpaque(ctx).takeUnretainedValue()

    let aorString = aor.map { String(cString: $0) }
    let callIDString = callID.map { String(cString: $0) }
    let peerString = peer.map { String(cString: $0) }
    let codeValue = Int(code)
    let eventValue = event

    Task {
        await bridge.handle(
            event: eventValue,
            aor: aorString,
            engineCallID: callIDString,
            peer: peerString,
            code: codeValue
        )
    }
}
