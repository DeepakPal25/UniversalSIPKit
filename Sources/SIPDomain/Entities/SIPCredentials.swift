import Foundation

/// Secret authentication material for a SIP account.
///
/// This type is kept separate from ``SIPAccount`` so that credentials never
/// leak into publicly observable account metadata, logs, or events. Instances
/// should be persisted only through a protected ``CredentialStoreProtocol``.
public struct SIPCredentials: Sendable, Equatable, Codable {

    /// The authentication user name. Often equal to the account user name but
    /// can differ depending on the SIP provider.
    public let authName: String

    /// The secret password or shared secret.
    public let password: String

    /// The authentication realm. When `nil`, the engine should fall back to a
    /// wildcard realm where the provider supports it.
    public let realm: String?

    public init(
        authName: String,
        password: String,
        realm: String? = nil
    ) {
        self.authName = authName
        self.password = password
        self.realm = realm
    }
}

extension SIPCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacts the password so credentials are never printed by accident.
    public var description: String {
        "SIPCredentials(authName: \(authName), password: <redacted>, realm: \(realm ?? "*"))"
    }

    public var debugDescription: String { description }
}
