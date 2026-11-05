import Foundation
import SIPDomain

#if canImport(CallKit) && os(iOS)
import CallKit
import AVFoundation

/// Actions the SDK core performs in response to CallKit user interactions.
///
/// The composition root supplies these closures so that CallKit stays decoupled
/// from the SIP engine and use cases.
public struct CallKitActions: Sendable {
    public var performAnswer: @Sendable (UUID) async -> Void
    public var performEnd: @Sendable (UUID) async -> Void
    public var performSetMuted: @Sendable (UUID, Bool) async -> Void
    public var performSetHeld: @Sendable (UUID, Bool) async -> Void
    public var performStartOutgoing: @Sendable (UUID) async -> Void

    public init(
        performAnswer: @escaping @Sendable (UUID) async -> Void,
        performEnd: @escaping @Sendable (UUID) async -> Void,
        performSetMuted: @escaping @Sendable (UUID, Bool) async -> Void,
        performSetHeld: @escaping @Sendable (UUID, Bool) async -> Void,
        performStartOutgoing: @escaping @Sendable (UUID) async -> Void
    ) {
        self.performAnswer = performAnswer
        self.performEnd = performEnd
        self.performSetMuted = performSetMuted
        self.performSetHeld = performSetHeld
        self.performStartOutgoing = performStartOutgoing
    }
}

/// Bridges the SDK to CallKit: reports incoming/outgoing calls and forwards
/// user actions back to the SIP core.
public final class CallKitManager: NSObject, @unchecked Sendable {

    private let provider: CXProvider
    private let callController = CXCallController()
    private let actions: CallKitActions
    private let logger = SIPLogger(category: .callkit)

    public init(localizedName: String = "UniversalSIPKit", actions: CallKitActions) {
        self.actions = actions

        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic, .phoneNumber]

        self.provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// Reports an incoming call to the system so the native UI appears. Must be
    /// called promptly after a VoIP push wakes the app.
    public func reportIncomingCall(
        id: UUID,
        remoteNumber: String
    ) async throws {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: remoteNumber)
        update.hasVideo = false

        do {
            try await provider.reportNewIncomingCall(with: id, update: update)
        } catch {
            logger.error("reportNewIncomingCall failed: \(error.localizedDescription)")
            throw SIPError.callFailed
        }
    }

    /// Requests that the system start an outgoing call transaction.
    public func startOutgoingCall(id: UUID, remoteNumber: String) async throws {
        let handle = CXHandle(type: .generic, value: remoteNumber)
        let action = CXStartCallAction(call: id, handle: handle)
        try await request(CXTransaction(action: action))
    }

    public func endCall(id: UUID) async throws {
        try await request(CXTransaction(action: CXEndCallAction(call: id)))
    }

    public func setHeld(id: UUID, held: Bool) async throws {
        try await request(CXTransaction(action: CXSetHeldCallAction(call: id, onHold: held)))
    }

    public func setMuted(id: UUID, muted: Bool) async throws {
        try await request(CXTransaction(action: CXSetMutedCallAction(call: id, muted: muted)))
    }

    /// Notifies CallKit that an outgoing call connected, and that a call ended.
    public func reportOutgoingConnected(id: UUID) {
        provider.reportOutgoingCall(with: id, connectedAt: nil)
    }

    public func reportCallEnded(id: UUID, reason: CXCallEndedReason = .remoteEnded) {
        provider.reportCall(with: id, endedAt: nil, reason: reason)
    }

    private func request(_ transaction: CXTransaction) async throws {
        do {
            try await callController.request(transaction)
        } catch {
            logger.error("CallKit transaction failed: \(error.localizedDescription)")
            throw SIPError.callFailed
        }
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {

    public func providerDidReset(_ provider: CXProvider) {
        logger.info("CallKit provider reset")
    }

    // Each handler captures only Sendable values (the call id / flags) in the
    // Task and fulfills the action synchronously, so no non-Sendable CallKit
    // action object crosses an isolation boundary.

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let id = action.callUUID
        let actions = self.actions
        Task { await actions.performStartOutgoing(id) }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let id = action.callUUID
        let actions = self.actions
        Task { await actions.performAnswer(id) }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let id = action.callUUID
        let actions = self.actions
        Task { await actions.performEnd(id) }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        let id = action.callUUID
        let held = action.isOnHold
        let actions = self.actions
        Task { await actions.performSetHeld(id, held) }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let id = action.callUUID
        let muted = action.isMuted
        let actions = self.actions
        Task { await actions.performSetMuted(id, muted) }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        logger.info("CallKit activated audio session")
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        logger.info("CallKit deactivated audio session")
    }
}
#endif
