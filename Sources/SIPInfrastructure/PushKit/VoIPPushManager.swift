import Foundation
import SIPDomain

#if canImport(PushKit) && os(iOS)
import PushKit

/// Registers for and receives VoIP pushes via PushKit.
///
/// PushKit integration is intentionally kept independent of SIP registration:
/// the token is reported to the host app (which forwards it to the VoIP push
/// gateway), and incoming pushes are surfaced so the SDK can promptly report a
/// call to CallKit. The app must report a genuine incoming call for every VoIP
/// push it receives.
public final class VoIPPushManager: NSObject, @unchecked Sendable {

    /// Called when the device VoIP push token updates. Forward this to the gateway.
    public var onTokenUpdate: (@Sendable (Data) -> Void)?

    /// Called when a VoIP push arrives. The handler must report a call to
    /// CallKit and then invoke the completion so iOS knows the push was handled.
    public var onIncomingPush: (@Sendable (_ payload: [AnyHashable: Any], _ completion: @escaping @Sendable () -> Void) -> Void)?

    private let registry: PKPushRegistry
    private let logger = SIPLogger(category: .push)

    public override init() {
        self.registry = PKPushRegistry(queue: .main)
        super.init()
        registry.delegate = self
    }

    /// Begins VoIP push registration. Requires the Voice over IP background mode.
    public func register() {
        registry.desiredPushTypes = [.voIP]
    }
}

/// Wraps PushKit's non-Sendable completion handler so it can be forwarded into
/// the host's `@Sendable` incoming-push handler and invoked exactly once.
private struct CompletionBox: @unchecked Sendable {
    private let completion: () -> Void
    init(_ completion: @escaping () -> Void) { self.completion = completion }
    func run() { completion() }
}

extension VoIPPushManager: PKPushRegistryDelegate {

    public func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        logger.info("Received VoIP push token update")
        onTokenUpdate?(pushCredentials.token)
    }

    public func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        logger.info("VoIP push token invalidated")
    }

    public func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else { completion(); return }
        logger.info("Received incoming VoIP push")

        guard let handler = onIncomingPush else {
            // We MUST still report a call or iOS may terminate the app. With no
            // handler configured, complete immediately.
            completion()
            return
        }
        // PushKit's completion is a non-Sendable closure delivered on the
        // registry queue; box it so it can be called back from the handler.
        let box = CompletionBox(completion)
        handler(payload.dictionaryPayload) { box.run() }
    }
}
#endif
