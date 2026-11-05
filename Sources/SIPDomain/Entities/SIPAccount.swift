import Foundation

/// A SIP account's publicly observable metadata.
///
/// Credentials are intentionally excluded from this entity. They are supplied
/// separately through ``SIPCredentials`` and persisted through a protected
/// ``CredentialStoreProtocol``.
public struct SIPAccount: Sendable, Identifiable, Equatable {

    public let id: UUID
    public let username: String
    public let domain: String
    public let port: Int
    public let transport: SIPTransport

    public init(
        id: UUID = UUID(),
        username: String,
        domain: String,
        port: Int = 5060,
        transport: SIPTransport = .udp
    ) {
        self.id = id
        self.username = username
        self.domain = domain
        self.port = port
        self.transport = transport
    }

    /// The fully-qualified SIP URI for this account, e.g. `sip:1001@example.com`.
    public var uri: String {
        let scheme = transport == .tls ? "sips" : "sip"
        return "\(scheme):\(username)@\(domain)"
    }
}
