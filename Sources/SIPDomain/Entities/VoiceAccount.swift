import Foundation

/// A provider-neutral account identity.
///
/// This is the universal account type the engine seam speaks, so the SDK can
/// drive SIP engines (Baresip, PJSIP) *and* non-SIP vendor SDKs (Twilio,
/// Vonage, Agora) behind one API. SIP-specific fields live in ``settings``
/// rather than being baked into the type.
public struct VoiceAccount: Sendable, Identifiable, Equatable {

    /// Well-known keys used in ``settings`` for SIP providers.
    public enum SettingKey {
        public static let domain = "domain"
        public static let port = "port"
        public static let transport = "transport"
    }

    public let id: UUID
    /// Identifies the provider that owns this account, e.g. `sip.baresip`,
    /// `sip.pjsip`, `twilio`.
    public let providerID: String
    /// The caller identity: a SIP username, or a vendor client identity.
    public let identity: String
    /// Provider-specific configuration (SIP domain/port/transport, vendor
    /// region, etc.). Opaque to the Domain layer.
    public let settings: [String: String]

    public init(
        id: UUID = UUID(),
        providerID: String,
        identity: String,
        settings: [String: String] = [:]
    ) {
        self.id = id
        self.providerID = providerID
        self.identity = identity
        self.settings = settings
    }
}

public extension SIPAccount {
    /// Projects a SIP account into the provider-neutral ``VoiceAccount``.
    func asVoiceAccount(providerID: String) -> VoiceAccount {
        VoiceAccount(
            id: id,
            providerID: providerID,
            identity: username,
            settings: [
                VoiceAccount.SettingKey.domain: domain,
                VoiceAccount.SettingKey.port: String(port),
                VoiceAccount.SettingKey.transport: transport.rawValue
            ]
        )
    }
}
