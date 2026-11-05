import Foundation
import SIPDomain
import BaresipBridge

/// Translates baresip's C callbacks into ``SIPCallEvent`` values and owns the
/// id/state bookkeeping that maps engine-assigned string ids to the SDK's
/// `UUID`-based model.
///
/// It is an `actor` so the call/account maps are mutated safely, whether the
/// mutation originates from the Swift engine (outgoing calls) or from a baresip
/// callback thread (incoming calls, state changes).
actor BaresipEventBridge {

    private let broadcaster = EventBroadcaster()

    /// aor ("sip:user@domain") → account id
    private var accountIDs: [String: UUID] = [:]
    /// engine call id → SDK call id
    private var callUUIDs: [String: UUID] = [:]
    /// SDK call id → engine call id
    private var engineCallIDs: [UUID: String] = [:]
    /// SDK call id → latest snapshot
    private var calls: [UUID: SIPCall] = [:]

    func subscribe() async -> AsyncStream<SIPCallEvent> {
        await broadcaster.subscribe()
    }

    // MARK: - Mapping (called by the engine for outgoing operations)

    func register(aor: String, accountID: UUID) {
        accountIDs[aor] = accountID
    }

    func unregister(aor: String) {
        accountIDs[aor] = nil
    }

    /// Records an outgoing call and returns its initial snapshot.
    func registerOutgoing(engineCallID: String, accountID: UUID, destination: String) -> SIPCall {
        let call = SIPCall(
            id: UUID(),
            accountID: accountID,
            remoteNumber: destination,
            isIncoming: false,
            state: .connecting
        )
        callUUIDs[engineCallID] = call.id
        engineCallIDs[call.id] = engineCallID
        calls[call.id] = call
        return call
    }

    func engineCallID(for id: UUID) -> String? { engineCallIDs[id] }

    func currentCalls() -> [SIPCall] { Array(calls.values) }

    // MARK: - Inbound events (dispatched from the C trampoline)

    func handle(event: usk_baresip_event, aor: String?, engineCallID: String?, peer: String?, code: Int) async {
        switch event {
        case USK_BARESIP_EV_REG_OK:
            if let id = accountIDs[aor ?? ""] {
                await broadcaster.emit(.registrationChanged(accountID: id, state: .registered))
            }
        case USK_BARESIP_EV_REG_FAIL:
            if let id = accountIDs[aor ?? ""] {
                await broadcaster.emit(.registrationChanged(accountID: id, state: .failed(reason: "SIP \(code)")))
            }
        case USK_BARESIP_EV_REG_GONE:
            if let id = accountIDs[aor ?? ""] {
                await broadcaster.emit(.registrationChanged(accountID: id, state: .unregistered))
            }

        case USK_BARESIP_EV_CALL_INCOMING:
            guard let engineCallID else { return }
            let accountID = accountIDs[aor ?? ""] ?? UUID()
            let call = SIPCall(
                id: UUID(),
                accountID: accountID,
                remoteNumber: peer ?? "unknown",
                isIncoming: true,
                state: .incoming
            )
            callUUIDs[engineCallID] = call.id
            engineCallIDs[call.id] = engineCallID
            calls[call.id] = call
            await broadcaster.emit(.incomingCall(call))

        case USK_BARESIP_EV_CALL_RINGING, USK_BARESIP_EV_CALL_PROGRESS:
            await updateState(engineCallID: engineCallID, to: .ringing)

        case USK_BARESIP_EV_CALL_ESTABLISHED:
            if let updated = await updateState(engineCallID: engineCallID, to: .connected) {
                await broadcaster.emit(.callConnected(callID: updated.id))
            }

        case USK_BARESIP_EV_CALL_CLOSED:
            if let engineCallID, let uuid = callUUIDs[engineCallID] {
                calls[uuid] = nil
                callUUIDs[engineCallID] = nil
                engineCallIDs[uuid] = nil
                await broadcaster.emit(.callEnded(callID: uuid))
            }

        default:
            break
        }
    }

    @discardableResult
    private func updateState(engineCallID: String?, to state: SIPCallState) async -> SIPCall? {
        guard let engineCallID, let uuid = callUUIDs[engineCallID], let call = calls[uuid] else { return nil }
        let updated = call.with(state: state)
        calls[uuid] = updated
        await broadcaster.emit(.callStateChanged(updated))
        return updated
    }
}
